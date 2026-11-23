// AMDCState: stage 2 of a home-made AMD power manager. Registers a minimal pmDispatch with xnu so that idle CPUs
// enter the ACPI C-state from \_SB.PLTF.Cxxx._CST (SSDT5 on the Framework 13 AMD): C2 = read I/O port 0x414
// (18 us), C3 = read I/O port 0x415 (350 us). Without a pmDispatch, machine_idle() only does sti;hlt (C1).
// Only MachineIdle is provided; xnu checks every other pmDispatch member for NULL. PM_DISPATCH_VERSION must be 102
// (xnu-12377 / MacKernelSDK) or pmKextRegister panics. The APIC timer keeps running in C-states here
// (sysctl machdep.cpu.thermal.invariant_APIC_timer = 1), so timer wakeups are not lost.
// boot-arg amdcst=0 (off) / 2 (C2, default) / 3 (C3).
#include <IOKit/IOService.h>
#include <IOKit/IOLib.h>
#include <IOKit/IOTimerEventSource.h>
#include <IOKit/IOWorkLoop.h>
#include <libkern/OSAtomic.h>
#include <pexpert/pexpert.h>

extern "C" {
void pmKextRegister(uint32_t version, void *cpuFuncs, void *callbacks);
void pmUnRegister(void *cpuFuncs);
}
static constexpr uint32_t kPMDispatchVersion = 102;

static void *gDispatch[40];        // pmDispatch_t: 29 function pointers in xnu-12377; index 2 = MachineIdle
static void *gCallbacks[128];      // pmCallBacks_t, filled by the kernel; index 2 = initComplete
static volatile SInt64 gIdleC2 = 0, gIdleC3 = 0;
static uint16_t gPort = 0x414;
static int gMode = 2;

static inline uint8_t inb(uint16_t port) { uint8_t v; __asm__ volatile("inb %1, %0" : "=a"(v) : "Nd"(port)); return v; }

// called by machine_idle() with interrupts disabled; return with them disabled. A pending interrupt makes the
// C-state exit at once (also when IF=0), and machine_idle's caller enables interrupts after we return.
static uint64_t amdMachineIdle(uint64_t maxIdleDuration) {
    (void)maxIdleDuration;
    (void)inb(gPort);
    if (gMode == 3) OSIncrementAtomic64(&gIdleC3); else OSIncrementAtomic64(&gIdleC2);
    return 0;
}

class AMDCState : public IOService {
    OSDeclareDefaultStructors(AMDCState)
    IOWorkLoop *fWL = nullptr;
    IOTimerEventSource *fTimer = nullptr;
    bool fRegistered = false;
    static void tick(OSObject *o, IOTimerEventSource *t) {
        AMDCState *s = (AMDCState *)o;
        s->setProperty("IdleEntriesC2", (unsigned long long)gIdleC2, 64);
        s->setProperty("IdleEntriesC3", (unsigned long long)gIdleC3, 64);
        t->setTimeoutMS(2000);
    }
public:
    bool start(IOService *provider) override {
        if (!IOService::start(provider)) return false;
        uint32_t r[4];
        __asm__ volatile("cpuid" : "=a"(r[0]), "=b"(r[1]), "=c"(r[2]), "=d"(r[3]) : "a"(0), "c"(0));
        const bool amd = r[1] == 0x68747541 && r[3] == 0x69746e65 && r[2] == 0x444d4163;   // "AuthenticAMD"
        __asm__ volatile("cpuid" : "=a"(r[0]), "=b"(r[1]), "=c"(r[2]), "=d"(r[3]) : "a"(1), "c"(0));
        const uint32_t fam = ((r[0] >> 8) & 0xf) + ((r[0] >> 20) & 0xff);
        int mode = 2;
        if (!PE_parse_boot_argn("amdcst", &mode, sizeof(mode))) mode = 2;
        setProperty("Mode", (unsigned long long)mode, 32);
        if (!amd || fam != 0x19 || (mode != 2 && mode != 3)) {
            IOLog("AMDCState: not enabled (amd %d family %02xh mode %d)\n", amd, fam, mode);
            setProperty("Enabled", false); registerService(); return true;
        }
        gMode = mode; gPort = mode == 3 ? 0x415 : 0x414;
        gDispatch[2] = (void *)&amdMachineIdle;
        pmKextRegister(kPMDispatchVersion, gDispatch, gCallbacks);
        fRegistered = true;
        if (gCallbacks[2]) ((void (*)(void))gCallbacks[2])();   // initComplete -> pmInitDone = 1
        setProperty("Enabled", true);
        setProperty("IdlePort", (unsigned long long)gPort, 16);
        IOLog("AMDCState: registered, idle reads port 0x%x (C%d)\n", gPort, mode);
        fWL = getWorkLoop();
        if (fWL) {
            fWL->retain();
            fTimer = IOTimerEventSource::timerEventSource(this, &AMDCState::tick);
            if (fTimer && fWL->addEventSource(fTimer) == kIOReturnSuccess) fTimer->setTimeoutMS(2000);
        }
        registerService();
        return true;
    }
    void stop(IOService *provider) override {
        if (fRegistered) { pmUnRegister(gDispatch); fRegistered = false; }
        if (fTimer) { fTimer->cancelTimeout(); if (fWL) fWL->removeEventSource(fTimer); fTimer->release(); fTimer = nullptr; }
        if (fWL) { fWL->release(); fWL = nullptr; }
        IOService::stop(provider);
    }
};
OSDefineMetaClassAndStructors(AMDCState, IOService)

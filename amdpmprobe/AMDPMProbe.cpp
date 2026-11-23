// AMDPMProbe: read-only probe of the AMD Zen power-management MSRs (stage 0 of a home-made power manager).
// Writes nothing to the CPU. Every MSR read is gated by the CPUID feature bit that guarantees the MSR exists,
// because an rdmsr of a missing MSR is a #GP (kernel panic) and xnu does not export a safe rdmsr to kexts.
// Results go to ioreg (class AMDPMProbe); a 1 s timer adds package power (RAPL) and the boot CPU's APERF/MPERF ratio.
#include <IOKit/IOService.h>
#include <IOKit/IOLib.h>
#include <IOKit/IOTimerEventSource.h>
#include <IOKit/IOWorkLoop.h>
#include <libkern/OSAtomic.h>

static inline void cpuid(uint32_t leaf, uint32_t sub, uint32_t r[4]) {
    __asm__ volatile("cpuid" : "=a"(r[0]), "=b"(r[1]), "=c"(r[2]), "=d"(r[3]) : "a"(leaf), "c"(sub));
}
static inline uint64_t rdmsr(uint32_t msr) {
    uint32_t lo, hi;
    __asm__ volatile("rdmsr" : "=a"(lo), "=d"(hi) : "c"(msr));
    return ((uint64_t)hi << 32) | lo;
}

// Reads MPERF and TSC back-to-back on the current CPU with interrupts off (pushf/cli ... popf, no kernel symbol needed),
// plus the CPU's initial APIC ID (CPUID 1 EBX[31:24]) so per-CPU deltas are never mixed across CPUs.
// MPERF counts only in C0 at the reference rate; TSC always counts at the same rate, so dMPERF/dTSC = C0 residency.
static inline void readC0(uint32_t *apic, uint64_t *mperf, uint64_t *tsc) {
    uint64_t fl; uint32_t r[4], lo, hi;
    __asm__ volatile("pushfq; popq %0; cli" : "=r"(fl) :: "memory");
    cpuid(1, 0, r);
    *apic = r[1] >> 24;
    *mperf = rdmsr(0xE7);
    __asm__ volatile("rdtsc" : "=a"(lo), "=d"(hi));
    *tsc = ((uint64_t)hi << 32) | lo;
    __asm__ volatile("pushq %0; popfq" :: "r"(fl) : "memory", "cc");
}

class AMDPMProbe : public IOService {
    OSDeclareDefaultStructors(AMDPMProbe)
    IOWorkLoop *fWL = nullptr;
    IOTimerEventSource *fTimer = nullptr;
    bool fRapl = false, fEff = false;
    uint32_t fEsuShift = 0;
    uint64_t fLastEnergy = 0, fLastNs = 0, fLastAperf = 0, fLastMperf = 0;
    uint64_t fC0Mperf[256] = {}, fC0Tsc[256] = {};   // last sample per APIC ID
    uint32_t fC0Permille[256] = {};                   // last C0 residency per APIC ID (0 = not seen yet)
    bool fC0Seen[256] = {};
    void hex(const char *k, uint64_t v) { char s[24]; snprintf(s, sizeof s, "0x%llx", (unsigned long long)v); setProperty(k, s); }
    static void tick(OSObject *owner, IOTimerEventSource *t) { ((AMDPMProbe *)owner)->sample(); t->setTimeoutMS(1000); }
    void sample() {
        uint64_t now; absolutetime_to_nanoseconds(mach_absolute_time(), &now);
        if (fRapl) {
            uint64_t e = rdmsr(0xC001029B) & 0xffffffffull;   // package energy counter (wraps at 32 bits)
            if (fLastNs) {
                uint64_t de = (e - fLastEnergy) & 0xffffffffull, dt = now - fLastNs;
                // energy unit = 1/2^ESU joule: uJ = de * 1e6 >> ESU (fits: de < 2^32), mW = uJ * 1e6 / dt_ns
                // (no 128-bit or floating-point math in a kext)
                uint64_t uj = (de * 1000000ull) >> fEsuShift;
                uint64_t mw = dt ? uj * 1000000ull / dt : 0;
                setProperty("PackagePowerMilliWatt", mw, 64);
            }
            fLastEnergy = e;
        }
        if (fEff) {
            uint64_t a = rdmsr(0xE8), m = rdmsr(0xE7);   // APERF, MPERF of the CPU running the timer
            if (fLastNs && m != fLastMperf) setProperty("APERFperMPERFx1000", (uint64_t)((a - fLastAperf) * 1000 / (m - fLastMperf)), 64);
            fLastAperf = a; fLastMperf = m;
            hex("PStateStatus", rdmsr(0xC0010063));
            // C0 residency of whichever CPU runs this timer (the work loop thread migrates, so over time several CPUs show up)
            uint32_t id; uint64_t mp, ts;
            readC0(&id, &mp, &ts);
            id &= 0xff;
            if (fC0Seen[id] && ts > fC0Tsc[id]) {
                uint64_t pm = (mp - fC0Mperf[id]) * 1000 / (ts - fC0Tsc[id]);
                fC0Permille[id] = (uint32_t)(pm > 1000 ? 1000 : pm) + 1;   // +1 so 0 means "no sample"
            }
            fC0Mperf[id] = mp; fC0Tsc[id] = ts; fC0Seen[id] = true;
            char k[24]; snprintf(k, sizeof k, "C0PermilleCPU%u", id);
            if (fC0Permille[id]) setProperty(k, fC0Permille[id] - 1, 32);
            uint64_t sum = 0, n = 0;
            for (uint32_t i = 0; i < 256; i++) if (fC0Permille[i]) { sum += fC0Permille[i] - 1; n++; }
            if (n) { setProperty("C0PermilleAvg", (uint32_t)(sum / n), 32); setProperty("C0CPUsSeen", (uint32_t)n, 32); }
        }
        fLastNs = now;
    }
public:
    bool start(IOService *provider) override {
        if (!IOService::start(provider)) return false;
        uint32_t r[4];
        cpuid(0, 0, r);
        char vendor[13]; memcpy(vendor, &r[1], 4); memcpy(vendor + 4, &r[3], 4); memcpy(vendor + 8, &r[2], 4); vendor[12] = 0;
        setProperty("Vendor", vendor);
        if (strcmp(vendor, "AuthenticAMD")) { IOLog("AMDPMProbe: not AMD, idle\n"); registerService(); return true; }
        cpuid(1, 0, r);
        const uint32_t fam = ((r[0] >> 8) & 0xf) + ((r[0] >> 20) & 0xff), model = ((r[0] >> 4) & 0xf) | (((r[0] >> 16) & 0xf) << 4);
        setProperty("Family", fam, 32); setProperty("Model", model, 32);
        if (fam < 0x17) { registerService(); return true; }   // the MSRs below are Zen-only
        uint32_t e7[4], e8[4], l6[4];
        cpuid(0x80000007, 0, e7); cpuid(0x80000008, 0, e8); cpuid(6, 0, l6);
        const bool cppc = (e8[1] >> 27) & 1;    // Fn8000_0008 EBX[27] CPPC
        fRapl = (e7[3] >> 14) & 1;              // Fn8000_0007 EDX[14] RAPL
        fEff = l6[2] & 1;                       // Fn0000_0006 ECX[0] APERF/MPERF
        setProperty("CPPCSupported", cppc); setProperty("RAPLSupported", fRapl); setProperty("APERFMPERFSupported", fEff);
        hex("CPUID_80000007_EDX", e7[3]); hex("CPUID_80000008_EBX", e8[1]);
        // architectural on every Zen
        hex("HWCR", rdmsr(0xC0010015));
        hex("PStateCurLimit", rdmsr(0xC0010061));
        hex("PStateCtl", rdmsr(0xC0010062));
        hex("PStateStatus", rdmsr(0xC0010063));
        for (uint32_t i = 0; i < 8; i++) { char k[16]; snprintf(k, sizeof k, "PStateDef%u", i); hex(k, rdmsr(0xC0010064 + i)); }
        // Zen C-state MSRs (AMD PPR Fam17h/19h): C001_0073 CStateBaseAddr — the I/O port whose read (+offset) enters
        // the deeper C-states; C001_0296 CStateConfig — per-level CC1/CC6 enables. Present on every Zen part.
        {
            uint64_t base = rdmsr(0xC0010073), cfg = rdmsr(0xC0010296);
            hex("CStateBaseAddr", base); hex("CStateConfig", cfg);
            setProperty("CStateIoPort", (uint32_t)(base & 0xffff), 32);
        }
        if (cppc) {
            hex("CPPCCapability1", rdmsr(0xC00102B0));
            hex("CPPCEnable", rdmsr(0xC00102B1));
            hex("CPPCCapability2", rdmsr(0xC00102B2));
            hex("CPPCRequest", rdmsr(0xC00102B3));
            hex("CPPCStatus", rdmsr(0xC00102B4));
        }
        if (fRapl) {
            uint64_t u = rdmsr(0xC0010299);
            hex("RAPLPowerUnit", u);
            fEsuShift = (uint32_t)((u >> 8) & 0x1f);
        }
        fWL = getWorkLoop();
        if (fWL && (fRapl || fEff)) {
            fWL->retain();
            fTimer = IOTimerEventSource::timerEventSource(this, &AMDPMProbe::tick);
            if (fTimer && fWL->addEventSource(fTimer) == kIOReturnSuccess) fTimer->setTimeoutMS(1000);
        }
        IOLog("AMDPMProbe: family %02xh model %02xh cppc %d rapl %d aperf %d\n", fam, model, cppc, fRapl, fEff);
        registerService();
        return true;
    }
    void stop(IOService *provider) override {
        if (fTimer) { fTimer->cancelTimeout(); if (fWL) fWL->removeEventSource(fTimer); fTimer->release(); fTimer = nullptr; }
        if (fWL) { fWL->release(); fWL = nullptr; }
        IOService::stop(provider);
    }
};
OSDefineMetaClassAndStructors(AMDPMProbe, IOService)

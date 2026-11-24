/*
 * SSDT-S3（FW13）：只在 macOS 下、DSDT 沒有建立 \_S3 時，補一個 \_S3，讓 macOS 願意開始睡眠流程；另外把韌體的
 * CNSB／DAS3 露出來看。
 *
 * 為什麼（2026-11-25，power/HIBERNATE-PLAN.md）：PhxSleepPolicy 回答「休眠」之後，kernel 仍然
 * "PMRD: System sleep prevented by kPMPCIUnsupported"（AppleACPIPlatform 認為平台不能睡）。DSDT 第 860–871 行：
 *     If ((CNSB == Zero)) { If ((DAS3 == One)) { Name (_S3, Package (0x04) { 0x03, 0x03, Zero, Zero }) } }
 * Framework 13 AMD 是 Modern Standby，CachyOS 上也只有 s2idle → 推論 CNSB != 0，_S3 不存在。
 * S3 本身不會被進入：PhxSleepPolicy 只回答「休眠」（hibernatemode 開著）或「取消」。
 *
 * 做法照 660m-Metal（rthh21/660m-Metal，GPL-2.0）dist/acpi/SSDT-S3.dsl：同一款 Phoenix 筆電 DSDT 的同一個條件式。
 * 數值用 DSDT 自己的（SLP_TYP 3／3）。Windows／Linux 看不到（_OSI ("Darwin") 是 false；CachyOS 也不經過 OpenCore）。
 *
 * 診斷：\_SB.FWS3 的 _STA = 0x0B | DAS3 << 8 | CNSB << 16（只在 Darwin），AppleACPIPlatform 會把它放成 IOACPIPlane
 * 上 FWS3 的 "_STA" 屬性：ioreg -p IOACPIPlane -lw0 -n FWS3 | grep _STA
 *
 * 編譯：iasl -vx 6142 SSDT-S3.dsl
 *   iasl 做靜態命名空間檢查，會把「先 CondRefOf (\_S3) 再 Name (\_S3)」當成 6142 Illegal forward reference。
 *   載入表時 module-level code 依序執行，CondRefOf 先跑、只看得到 DSDT 的 _S3，這正是要的行為。
 * 移除：config.plist ACPI.Add 把它停用。
 */
DefinitionBlock ("", "SSDT", 2, "FW13", "S3HIB", 0x00000000)
{
    External (CNSB, FieldUnitObj)
    External (DAS3, FieldUnitObj)

    If (_OSI ("Darwin"))
    {
        If (LNot (CondRefOf (\_S3)))
        {
            Name (\_S3, Package (0x04)
            {
                0x03,
                0x03,
                Zero,
                Zero
            })
        }
    }

    Device (\_SB.FWS3)
    {
        Name (_HID, "FW130003")  // _HID: Hardware ID
        Method (_STA, 0, NotSerialized)  // _STA: Status
        {
            If (_OSI ("Darwin"))
            {
                Return (Or (0x0B, Or (ShiftLeft (\DAS3, 0x08), ShiftLeft (\CNSB, 0x10))))
            }

            Return (Zero)
        }
    }
}

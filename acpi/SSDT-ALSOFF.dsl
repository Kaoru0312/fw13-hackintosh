/*
 * SSDT-ALSOFF: hide the Framework EC ambient light sensor (\_SB.I2CA.ECS2, FRMW0005) from macOS only.
 * VoodooI2CHID polls I2C HID devices that never report multitouch every 5 ms forever; this one is unused by macOS.
 * If ECS2 already defines _STA in the DSDT, this table fails to load (AE_ALREADY_EXISTS) and changes nothing.
 */
DefinitionBlock ("", "SSDT", 2, "FW13", "ALSOFF", 0x00000000)
{
    External (_SB_.I2CA.ECS2, DeviceObj)

    Scope (_SB.I2CA.ECS2)
    {
        Method (_STA, 0, NotSerialized)
        {
            If (_OSI ("Darwin"))
            {
                Return (Zero)
            }

            Return (0x0F)
        }
    }
}

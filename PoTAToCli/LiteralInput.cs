using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Runtime.InteropServices;

// Unicode keyboard events, never clipboard or application object-model writes.
public static class PotatoLiteralInput {
    [StructLayout(LayoutKind.Sequential)]
    struct KeyboardInput { public ushort key, scan; public uint flags, time; public IntPtr extra; }
    [StructLayout(LayoutKind.Sequential)]
    struct MouseInput { public int x, y; public uint data, flags, time; public IntPtr extra; }
    [StructLayout(LayoutKind.Explicit)]
    struct InputUnion {
        [FieldOffset(0)] public KeyboardInput keyboard;
        [FieldOffset(0)] public MouseInput mouse;
    }
    [StructLayout(LayoutKind.Sequential)]
    struct Input { public uint type; public InputUnion value; }
    [DllImport("user32.dll", SetLastError=true)]
    static extern uint SendInput(uint count, Input[] input, int size);

    static Input Key(char value, bool up) {
        bool control = value == '\n' || value == '\t';
        return new Input { type=1, value=new InputUnion { keyboard=new KeyboardInput {
            key=(ushort)(control ? (value == '\n' ? 13 : 9) : 0),
            scan=(ushort)(control ? 0 : value), flags=(control ? 0u : 4u) | (up ? 2u : 0u)
        } } };
    }
    public static void SendText(string text) {
        text = text.Replace("\r\n", "\n").Replace("\r", "\n");
        for (int offset=0; offset<text.Length;) {
            int length=Math.Min(128,text.Length-offset);
            if (offset+length<text.Length && char.IsHighSurrogate(text[offset+length-1])) length--;
            var inputs=new Input[length*2];
            for (int i=0;i<length;i++) {
                inputs[i*2]=Key(text[offset+i],false);
                inputs[i*2+1]=Key(text[offset+i],true);
            }
            uint sent=SendInput((uint)inputs.Length,inputs,Marshal.SizeOf(typeof(Input)));
            if (sent!=inputs.Length)
                throw new Win32Exception(Marshal.GetLastWin32Error(), "Text input was incomplete; observe the field before retrying.");
            offset+=length;
        }
    }
}

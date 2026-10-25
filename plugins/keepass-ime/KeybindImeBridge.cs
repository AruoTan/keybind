using System;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Windows.Forms;
using KeePass.Plugins;
using KeePass.Util;
using KeePass.Util.SendInputExt;

[assembly: AssemblyTitle("Keybind IME Bridge")]
[assembly: AssemblyProduct("KeePass Plugin")]
[assembly: AssemblyDescription("Preserve IME state around KeePass auto-type using keybind.ahk.")]

namespace KeybindImeBridge
{
    public sealed class KeybindImeBridgeExt : Plugin
    {
        public override bool Initialize(IPluginHost host)
        {
            if (host == null) return false;
            SendInputEx.CreateEngine += OnCreateEngine;
            return true;
        }

        public override void Terminate()
        {
            SendInputEx.CreateEngine -= OnCreateEngine;
        }

        private static void OnCreateEngine(object sender, SiEventArgs e)
        {
            ISiEngine engine = e.Engine;
            if (engine == null)
            {
                // KeePass exposes CreateEngine/ISiEngine publicly, but its default
                // Windows implementation is internal in KeePass 2.61.1.
                Type type = typeof(SendInputEx).Assembly.GetType(
                    "KeePass.Util.SendInputExt.SiEngineWin", true);
                engine = (ISiEngine)Activator.CreateInstance(type, true);
            }
            e.Engine = new ImeEngine(engine);
        }
    }

    // KeePass calls Release in a finally block, including cancellation and Init errors.
    // Delegate every input operation unchanged to KeePass (or an existing plugin engine).
    internal sealed class ImeEngine : ISiEngine
    {
        private readonly ISiEngine inner;
        private IntPtr receiver;
        private IntPtr target;
        private bool innerStarted;
        private static readonly uint Message = RegisterWindowMessage("Keybind.KeePassImeBridge.v1");

        internal ImeEngine(ISiEngine innerEngine) { inner = innerEngine; }

        public void Init()
        {
            receiver = FindWindow(null, "Keybind.KeePassImeBridge.v1");
            target = GetForegroundWindow();
            if (receiver == IntPtr.Zero || target == IntPtr.Zero || Message == 0)
                throw new InvalidOperationException(
                    "IME bridge unavailable. Please start the updated keybind-ahk.exe before auto-type.");

            // Release also sends restore if begin failed after partially changing the IME.
            if (!Notify(1))
                throw new InvalidOperationException(
                    "Could not save the input method state or switch to English. Auto-type was cancelled.");

            innerStarted = true;
            inner.Init();
            // Init can release held Shift/Alt keys; reassert English afterwards.
            if (!Notify(2))
                throw new InvalidOperationException(
                    "Could not keep the input method in English. Auto-type was cancelled.");
        }

        public void Release()
        {
            try
            {
                if (innerStarted) inner.Release();
            }
            finally
            {
                if (receiver != IntPtr.Zero && target != IntPtr.Zero && !Notify(3))
                    MessageBox.Show(
                        "The original input method state could not be restored. Please check the input method indicator.",
                        "Keybind IME Bridge", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                receiver = IntPtr.Zero;
                target = IntPtr.Zero;
            }
        }

        private bool Notify(int action)
        {
            UIntPtr result;
            return SendMessageTimeout(receiver, Message, new UIntPtr((uint)action),
                target, 0x2, 5000, out result) != IntPtr.Zero && result.ToUInt64() == 1;
        }

        public void UpdateExpectedFocus() { inner.UpdateExpectedFocus(); }
        public void SendKey(int key, bool? extended, bool? down) { inner.SendKey(key, extended, down); }
        public void SetKeyModifier(Keys key, bool down) { inner.SetKeyModifier(key, down); }
        public void SendChar(char value, bool? down) { inner.SendChar(value, down); }
        public void Delay(uint milliseconds) { inner.Delay(milliseconds); }

        [DllImport("user32.dll", CharSet = CharSet.Unicode)]
        private static extern uint RegisterWindowMessage(string name);
        [DllImport("user32.dll", CharSet = CharSet.Unicode)]
        private static extern IntPtr FindWindow(string className, string title);
        [DllImport("user32.dll")]
        private static extern IntPtr GetForegroundWindow();
        [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern IntPtr SendMessageTimeout(IntPtr window, uint message,
            UIntPtr wParam, IntPtr lParam, uint flags, uint timeout, out UIntPtr result);
    }
}

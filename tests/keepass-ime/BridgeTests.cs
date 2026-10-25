using System;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Windows.Forms;
using KeePass.Util.SendInputExt;
using KeybindImeBridge;

internal sealed class FakeEngine : ISiEngine
{
    internal bool FailInit;
    internal bool Released;
    internal int Calls;
    public void Init() { ++Calls; if (FailInit) throw new ApplicationException("simulated init failure"); }
    public void Release() { Released = true; }
    public void UpdateExpectedFocus() { ++Calls; }
    public void SendKey(int k, bool? e, bool? d) { ++Calls; }
    public void SetKeyModifier(Keys k, bool d) { ++Calls; }
    public void SendChar(char c, bool? d) { ++Calls; }
    public void Delay(uint ms) { ++Calls; }
}

internal static class BridgeTests
{
    [DllImport("user32.dll")] static extern IntPtr GetForegroundWindow();
    [DllImport("imm32.dll")] static extern IntPtr ImmGetDefaultIMEWnd(IntPtr hWnd);
    [DllImport("user32.dll")] static extern IntPtr SendMessage(IntPtr hWnd, uint msg, IntPtr w, IntPtr l);

    static long Ime(IntPtr h, int command, int value)
    { return SendMessage(h, 0x283, new IntPtr(command), new IntPtr(value)).ToInt64(); }

    static void Check(bool condition, string message)
    { if (!condition) throw new Exception(message); }

    [STAThread]
    static int Main()
    {
        try
        {
            // Verify that the installed KeePass version can construct the default engine.
            SiEventArgs args = new SiEventArgs();
            typeof(KeybindImeBridgeExt).GetMethod("OnCreateEngine",
                BindingFlags.Static | BindingFlags.NonPublic).Invoke(null, new object[] { null, args });
            Check(args.Engine is ImeEngine, "Engine factory failed");

            using (Form window = new Form())
            using (TextBox box = new TextBox())
            {
                window.Text = "KeePass IME integration test (no credentials)";
                window.Controls.Add(box);
                window.Show();
                window.Activate();
                box.Focus();
                Application.DoEvents();
                Check(GetForegroundWindow() == window.Handle, "Test window could not get focus");
                IntPtr ime = ImmGetDefaultIMEWnd(box.Handle);
                Check(ime != IntPtr.Zero, "Test window has no IME");
                int savedOpen = (int)Ime(ime, 5, 0);
                int savedConversion = (int)Ime(ime, 1, 0);
                try
                {
                    for (int state = 0; state <= 1; ++state)
                    {
                        Ime(ime, 6, state);
                        FakeEngine fake = new FakeEngine();
                        ImeEngine wrapper = new ImeEngine(fake);
                        try
                        {
                            wrapper.Init();
                            Check(Ime(ime, 5, 0) == 0, "English handshake failed");
                            wrapper.UpdateExpectedFocus();
                            wrapper.SendKey(9, null, null);
                            wrapper.SetKeyModifier(Keys.Control, false);
                            wrapper.SendChar('x', null);
                            wrapper.Delay(1);
                            Check(fake.Calls == 6, "Input operations were not delegated");
                        }
                        finally { wrapper.Release(); }
                        Check(fake.Released, "Inner engine was not released");
                        Check(Ime(ime, 5, 0) == state, "Original state was not restored");
                        Console.WriteLine("PASS: cross-process handshake, delegation, restore, initial state " + state);
                    }

                    Ime(ime, 6, 1);
                    FakeEngine failing = new FakeEngine();
                    failing.FailInit = true;
                    ImeEngine errorWrapper = new ImeEngine(failing);
                    bool threw = false;
                    try { errorWrapper.Init(); }
                    catch (ApplicationException) { threw = true; }
                    finally { errorWrapper.Release(); }
                    Check(threw && failing.Released && Ime(ime, 5, 0) == 1,
                        "Init exception did not restore the original state");
                    Console.WriteLine("PASS: initialization exception cleanup");

                    Ime(ime, 6, 1);
                    ImeEngine cancelled = new ImeEngine(new FakeEngine());
                    try
                    {
                        cancelled.Init();
                        throw new OperationCanceledException();
                    }
                    catch (OperationCanceledException) { }
                    finally { cancelled.Release(); }
                    Check(Ime(ime, 5, 0) == 1, "Cancellation did not restore the original state");
                    Console.WriteLine("PASS: cancellation cleanup");
                }
                finally
                {
                    Ime(ime, 6, savedOpen);
                    Ime(ime, 2, savedConversion);
                }
            }
            return 0;
        }
        catch (Exception ex)
        {
            Console.Error.WriteLine("FAIL: " + ex.Message);
            return 1;
        }
    }
}
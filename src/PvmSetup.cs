using System;
using System.IO;
using System.Reflection;
using System.Runtime.InteropServices;

[assembly: AssemblyTitle("PVM for Windows Setup")]
[assembly: AssemblyCompany("PVM")]
[assembly: AssemblyProduct("PVM for Windows")]
[assembly: AssemblyDescription("Python version manager for Windows")]
[assembly: AssemblyVersion("1.0.0.0")]
[assembly: AssemblyFileVersion("1.0.0.0")]

internal static class PvmSetup
{
    private static readonly IntPtr BroadcastWindow = new IntPtr(0xffff);
    private const uint WmSettingChange = 0x001A;

    [DllImport("user32.dll", CharSet = CharSet.Auto, SetLastError = true)]
    private static extern IntPtr SendMessageTimeout(IntPtr hWnd, uint message, UIntPtr wParam,
        string lParam, uint flags, uint timeout, out UIntPtr result);

    private static readonly string PvmHome = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), ".pvm");

    private static void Extract(string resourceName, string path)
    {
        using (Stream input = Assembly.GetExecutingAssembly().GetManifestResourceStream(resourceName))
        {
            if (input == null) throw new InvalidOperationException("Missing installer payload: " + resourceName);
            using (FileStream output = File.Create(path)) input.CopyTo(output);
        }
    }

    private static void AddPvmToUserPath()
    {
        string userPath = Environment.GetEnvironmentVariable("Path", EnvironmentVariableTarget.User) ?? "";
        string normalizedHome = PvmHome.TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar);
        foreach (string part in userPath.Split(new char[] { ';' }, StringSplitOptions.RemoveEmptyEntries))
        {
            if (String.Equals(part.Trim().TrimEnd('\\', '/'), normalizedHome.TrimEnd('\\', '/'), StringComparison.OrdinalIgnoreCase))
                return;
        }
        string updated = String.IsNullOrWhiteSpace(userPath) ? PvmHome : PvmHome + ";" + userPath;
        Environment.SetEnvironmentVariable("Path", updated, EnvironmentVariableTarget.User);
        UIntPtr result;
        SendMessageTimeout(BroadcastWindow, WmSettingChange, UIntPtr.Zero, "Environment", 0x0002, 5000, out result);
    }

    private static string GetArchitecture()
    {
        string arch = Environment.GetEnvironmentVariable("PROCESSOR_ARCHITEW6432");
        if (String.IsNullOrEmpty(arch)) arch = Environment.GetEnvironmentVariable("PROCESSOR_ARCHITECTURE");
        if (String.Equals(arch, "ARM64", StringComparison.OrdinalIgnoreCase)) return "arm64";
        if (Environment.Is64BitOperatingSystem) return "amd64";
        return "win32";
    }

    private static void CreateStartMenuShortcut()
    {
        string programs = Environment.GetFolderPath(Environment.SpecialFolder.Programs);
        Directory.CreateDirectory(programs);
        string shortcutPath = Path.Combine(programs, "PVM for Windows.lnk");
        string commandPrompt = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System), "cmd.exe");
        Type shellType = Type.GetTypeFromProgID("WScript.Shell");
        if (shellType == null) throw new InvalidOperationException("Windows Script Host is unavailable; could not create the Start Menu shortcut.");

        object shell = Activator.CreateInstance(shellType);
        object shortcut = null;
        try
        {
            shortcut = shellType.InvokeMember("CreateShortcut", BindingFlags.InvokeMethod, null, shell, new object[] { shortcutPath });
            Type shortcutType = shortcut.GetType();
            shortcutType.InvokeMember("TargetPath", BindingFlags.SetProperty, null, shortcut, new object[] { commandPrompt });
            shortcutType.InvokeMember("Arguments", BindingFlags.SetProperty, null, shortcut,
                new object[] { "/K \"title PVM for Windows & pvm.exe help\"" });
            shortcutType.InvokeMember("WorkingDirectory", BindingFlags.SetProperty, null, shortcut, new object[] { PvmHome });
            shortcutType.InvokeMember("IconLocation", BindingFlags.SetProperty, null, shortcut,
                new object[] { Path.Combine(PvmHome, "pvm.exe") + ",0" });
            shortcutType.InvokeMember("Description", BindingFlags.SetProperty, null, shortcut,
                new object[] { "Python Version Manager for Windows" });
            shortcutType.InvokeMember("Save", BindingFlags.InvokeMethod, null, shortcut, null);
        }
        finally
        {
            if (shortcut != null && Marshal.IsComObject(shortcut)) Marshal.FinalReleaseComObject(shortcut);
            if (Marshal.IsComObject(shell)) Marshal.FinalReleaseComObject(shell);
        }
    }

    private static int Main(string[] args)
    {
        try
        {
            Directory.CreateDirectory(PvmHome);
            Directory.CreateDirectory(Path.Combine(PvmHome, "versions"));
            Directory.CreateDirectory(Path.Combine(PvmHome, "cache"));

            Extract("payload.pvm.ps1", Path.Combine(PvmHome, "pvm.ps1"));
            Extract("payload.pvm.cmd", Path.Combine(PvmHome, "pvm.cmd"));
            Extract("payload.pvm.exe", Path.Combine(PvmHome, "pvm.exe"));
            Extract("payload.install.ps1", Path.Combine(PvmHome, "install.ps1"));

            string settings = Path.Combine(PvmHome, "settings.json");
            if (!File.Exists(settings))
                File.WriteAllText(settings, "{\r\n  \"enabled\": true,\r\n  \"arch\": \"" + GetArchitecture() + "\"\r\n}\r\n");

            AddPvmToUserPath();
            CreateStartMenuShortcut();

            Console.WriteLine();
            Console.WriteLine("PVM for Windows is installed.");
            Console.WriteLine("Start Menu: PVM for Windows");
            Console.WriteLine("PVM home: " + PvmHome);
            Console.WriteLine();
            Console.WriteLine("Open a new terminal, then run:");
            Console.WriteLine("  pvm list-remote");
            Console.WriteLine("  pvm install 3.12");
            Console.WriteLine("  pvm use 3.12");
            Console.WriteLine();
            return 0;
        }
        catch (Exception ex)
        {
            Console.Error.WriteLine("PVM setup failed: " + ex.Message);
            return 1;
        }
    }
}

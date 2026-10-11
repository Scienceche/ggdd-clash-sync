// core-wrapper.cs - Clash Verge Rev core wrapper for the GGDD patched mihomo
// Why this exists: CVR v2.5.8 hardcodes `tun: {enable: false, stack: mips}` into every
// generated config. Stock mihomo tolerates the unknown stack value; GGDD's patched core
// fatals with "Parse config error: invalid tun stack". This wrapper rewrites
// stack: mips -> stack: mixed in the -f config (and the -d dir yaml files) before
// exec'ing verge-mihomo-real.exe, and ties the child to a kill-on-close Job Object so
// CVR's process lifecycle management keeps working.
// Rebuild:
//   C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe /nologo /out:verge-mihomo.exe core-wrapper.cs
using System;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;

class CoreWrapper
{
    [DllImport("kernel32.dll", SetLastError = true)]
    static extern IntPtr CreateJobObject(IntPtr lpJobAttributes, string lpName);

    [DllImport("kernel32.dll", SetLastError = true)]
    static extern bool SetInformationJobObject(IntPtr hJob, int infoClass,
        ref JOBOBJECT_EXTENDED_LIMIT_INFORMATION lpInfo, int cbInfo);

    [DllImport("kernel32.dll", SetLastError = true)]
    static extern bool AssignProcessToJobObject(IntPtr hJob, IntPtr hProcess);

    [DllImport("kernel32.dll", SetLastError = true)]
    static extern bool CloseHandle(IntPtr hObject);

    [StructLayout(LayoutKind.Sequential)]
    struct JOBOBJECT_BASIC_LIMIT_INFORMATION
    {
        public long PerProcessUserTimeLimit;
        public long PerJobUserTimeLimit;
        public ushort LimitFlags;
        public UIntPtr MinimumWorkingSetSize;
        public UIntPtr MaximumWorkingSetSize;
        public uint ActiveProcessLimit;
        public UIntPtr Affinity;
        public uint PriorityClass;
        public uint SchedulingClass;
    }

    [StructLayout(LayoutKind.Sequential)]
    struct IO_COUNTERS
    {
        public ulong ReadOperationCount;
        public ulong WriteOperationCount;
        public ulong OtherOperationCount;
        public ulong ReadTransferCount;
        public ulong WriteTransferCount;
        public ulong OtherTransferCount;
    }

    [StructLayout(LayoutKind.Sequential)]
    struct JOBOBJECT_EXTENDED_LIMIT_INFORMATION
    {
        public JOBOBJECT_BASIC_LIMIT_INFORMATION BasicLimitInformation;
        public IO_COUNTERS IoInfo;
        public UIntPtr ProcessMemoryLimit;
        public UIntPtr JobMemoryLimit;
        public UIntPtr PeakProcessMemoryUsed;
        public UIntPtr PeakJobMemoryUsed;
    }

    const int JobObjectExtendedLimitInformationClass = 9;
    const ushort JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE = 0x2000;

    static string FindArgValue(string[] args, params string[] flags)
    {
        for (int i = 0; i < args.Length - 1; i++)
            foreach (string f in flags)
                if (args[i] == f) return args[i + 1];
        return null;
    }

    static void PatchFile(string path)
    {
        try
        {
            if (!File.Exists(path)) return;
            string text = File.ReadAllText(path, Encoding.UTF8);
            string patched = text.Replace("stack: mips", "stack: mixed");
            if (patched != text)
            {
                File.WriteAllText(path, patched, new UTF8Encoding(false));
                Console.Error.WriteLine("[wrapper] patched tun stack in " + path);
            }
        }
        catch (Exception e)
        {
            Console.Error.WriteLine("[wrapper] patch failed " + path + ": " + e.Message);
        }
    }

    static string Quote(string a)
    {
        return a.Contains(" ") ? "\"" + a + "\"" : a;
    }

    static int Main(string[] args)
    {
        string dir = AppDomain.CurrentDomain.BaseDirectory;
        string real = Path.Combine(dir, "verge-mihomo-real.exe");
        if (!File.Exists(real))
        {
            Console.Error.WriteLine("[wrapper] FATAL: " + real + " missing");
            return 1;
        }

        // rewrite tun stack sentinel in the generated config + config-dir yaml files
        string cfg = FindArgValue(args, "-f", "--config");
        string cfgDir = FindArgValue(args, "-d", "--dir");
        if (cfg != null) PatchFile(cfg);
        if (cfgDir != null)
        {
            try { foreach (string f in Directory.GetFiles(cfgDir, "*.yaml")) PatchFile(f); }
            catch { }
        }

        var psi = new ProcessStartInfo
        {
            FileName = real,
            Arguments = string.Join(" ", Array.ConvertAll(args, new Converter<string, string>(Quote))),
            UseShellExecute = false,
            CreateNoWindow = false
        };

        Process p;
        try { p = Process.Start(psi); }
        catch (Exception e)
        {
            Console.Error.WriteLine("[wrapper] FATAL: cannot start real core: " + e.Message);
            return 1;
        }

        // kill-on-close job: if CVR kills this wrapper, the real core dies with it
        IntPtr job = CreateJobObject(IntPtr.Zero, null);
        if (job != IntPtr.Zero)
        {
            var info = new JOBOBJECT_EXTENDED_LIMIT_INFORMATION();
            info.BasicLimitInformation.LimitFlags = JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE;
            SetInformationJobObject(job, JobObjectExtendedLimitInformationClass,
                ref info, Marshal.SizeOf(typeof(JOBOBJECT_EXTENDED_LIMIT_INFORMATION)));
            AssignProcessToJobObject(job, p.Handle);
        }

        p.WaitForExit();
        if (job != IntPtr.Zero) CloseHandle(job);
        return p.ExitCode;
    }
}

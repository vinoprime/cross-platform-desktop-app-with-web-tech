

using System.Diagnostics;
using System.Net;
using System.Net.Sockets;

var appBaseDir = AppContext.BaseDirectory;

/*
    In an MSIX / published build the web-ui dist is deployed alongside
    the host in a wwwroot/ subfolder. In a development build we want to be able to run the host
 */

var packageWebRoot = Path.GetFullPath(Path.Combine(appBaseDir, "wwwroot"));
var repoRoot = Path.GetFullPath(Path.Combine(appBaseDir, "..", "..", "..", "..", ".."));
var devContentRoot = Path.GetFullPath(Path.Combine(repoRoot, "DesktopHost", "DesktopHost"));
var devWebRoot = Path.GetFullPath(Path.Combine(repoRoot, "web-app", "dist", "MyAppName"));


var isPackaged = Directory.Exists(packageWebRoot);
var contentRootPath = isPackaged ? packageWebRoot : devContentRoot;
var webRootPath = isPackaged ? packageWebRoot : devWebRoot;

if (!Directory.Exists(webRootPath))
{
    throw new DirectoryNotFoundException($"Web root was not found at '{webRootPath}'. Build the frontend first with 'npm run build' or 'npm run build:watch' from the web-app folder.");
}

var builder = WebApplication.CreateBuilder(new WebApplicationOptions
{
    Args = args,
    ContentRootPath = contentRootPath,
    WebRootPath = webRootPath
});

const int preferredPort = 5173;
const int maxPort = 5200;
var localUrl = SelectLocalUrl(preferredPort, maxPort);


builder.WebHost.UseUrls(localUrl);

var app = builder.Build();

app.UseDefaultFiles();
app.UseStaticFiles();

app.MapGet("/health", () => Results.Ok(new { status = "OK" }));
app.MapFallbackToFile("index.html");

Process? launchedBrowserProcess = null;
var browserLaunchTimeUtc = DateTime.UtcNow;


app.Lifetime.ApplicationStarted.Register(() =>
{
    browserLaunchTimeUtc = DateTime.UtcNow;
    launchedBrowserProcess = LaunchInAppMode(localUrl);

    if (launchedBrowserProcess is null) return;

    launchedBrowserProcess.EnableRaisingEvents = true;
    launchedBrowserProcess.Exited += (_, _) =>
    {
        // Browsers can occasionally spawn a short-lived process that exits immediately, so we check the launch time to avoid false positives
        if (DateTime.UtcNow - browserLaunchTimeUtc < TimeSpan.FromSeconds(3))
        {
            return;
        }

        app.Lifetime.StopApplication();
    };
});


app.Lifetime.ApplicationStopping.Register(() =>
{
    TryKillProcess(launchedBrowserProcess);
});

app.Run();

static Process? LaunchInAppMode(string url)
{
    var appProfileDir = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "MyAppName", "browser-profile");

    Directory.CreateDirectory(appProfileDir);


    var browserExecutables = new[] {
    "chrome.exe",
    "msedge.exe"
    };


    foreach (var browserExe in browserExecutables)
    {
        try
        {
            var psi = new ProcessStartInfo
            {
                FileName = browserExe,
                Arguments = $"--app=\"{url}\" --new-window --user-data-dir=\"{appProfileDir}\" --no-first-run",
                UseShellExecute = true
            };
            var process = Process.Start(psi);

            if (process is not null)
            {
                return process;
            }
        }
        catch
        {
            /* Ignore and try next browser */
        }
    }
    LaunchDefaultBrowser(url);
    return null;

}

static void LaunchDefaultBrowser(string url)
{
    try
    {
        var psi = new ProcessStartInfo
        {
            FileName = url,
            UseShellExecute = true
        };
        Process.Start(psi);
    }
    catch (Exception ex)
    {
        Console.WriteLine($"Failed to launch browser: {ex.Message}");
    }
}



static void TryKillProcess(Process? process)
{
    if (process is null) return;


    try
    {
        if (!process.HasExited)
        {
            process.Kill(entireProcessTree: true);
        }
    }
    catch (Exception)
    {
        /* Process may already be gone or inaccessible */

    }

}




static string SelectLocalUrl(int preferredPort, int maxPort)
{
    for (int port = preferredPort; port <= maxPort; port++)
    {
        if (!IsPortAvailable(port))
        {
            continue;
        }

        if (port != preferredPort)
        {
            Console.WriteLine($"Preferred port {preferredPort} is in use. Using available port {port} instead.");
        }

        return $"http://127.0.0.1:{port}";
    }
    throw new InvalidOperationException($"No free loopback ports found between {preferredPort} and {maxPort}");
}

static bool IsPortAvailable(int port)
{
    TcpListener? listener = null;
    try
    {
        listener = new TcpListener(IPAddress.Loopback, port);
        listener.Start();
        return true;
    }
    catch (SocketException)
    {
        return false;
    }
    finally
    {
        listener?.Stop();
    }
}




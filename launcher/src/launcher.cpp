// LevelDevilLauncher
// - Optionally waits for an existing game process to exit (--wait-pid <PID>)
// - Queries GitHub Releases API for the latest release of alexverdes666/level_devil
// - If the latest tag differs from the local version.txt, downloads game.exe and
//   replaces the on-disk copy
// - Launches game.exe and exits
//
// Designed to ship next to game.exe. Uses only the Windows SDK + WinHTTP — no
// external runtime dependencies. Built with /MT so no VCRedist is required.

#include <windows.h>
#include <winhttp.h>
#include <shlwapi.h>
#include <shellapi.h>

#include <cstdio>
#include <cstdint>
#include <cstring>
#include <fstream>
#include <optional>
#include <sstream>
#include <string>
#include <vector>

#pragma comment(lib, "winhttp.lib")
#pragma comment(lib, "shlwapi.lib")
#pragma comment(lib, "shell32.lib")

namespace {

constexpr const wchar_t* kRepoOwner = L"alexverdes666";
constexpr const wchar_t* kRepoName  = L"level_devil";
constexpr const wchar_t* kApiHost   = L"api.github.com";
constexpr const wchar_t* kUserAgent = L"LevelDevilLauncher/1.0";
constexpr const wchar_t* kGameExe   = L"game.exe";
constexpr const wchar_t* kVersionFile = L"version.txt";
constexpr const wchar_t* kAssetName = L"game.exe";

// ---------- small utils ----------

std::wstring utf8_to_wide(const std::string& s) {
    if (s.empty()) return {};
    int n = MultiByteToWideChar(CP_UTF8, 0, s.data(), (int)s.size(), nullptr, 0);
    std::wstring out(n, L'\0');
    MultiByteToWideChar(CP_UTF8, 0, s.data(), (int)s.size(), out.data(), n);
    return out;
}

std::string wide_to_utf8(const std::wstring& s) {
    if (s.empty()) return {};
    int n = WideCharToMultiByte(CP_UTF8, 0, s.data(), (int)s.size(), nullptr, 0, nullptr, nullptr);
    std::string out(n, '\0');
    WideCharToMultiByte(CP_UTF8, 0, s.data(), (int)s.size(), out.data(), n, nullptr, nullptr);
    return out;
}

std::wstring trim(std::wstring s) {
    while (!s.empty() && (s.back() == L'\n' || s.back() == L'\r' || s.back() == L' ' || s.back() == L'\t'))
        s.pop_back();
    size_t i = 0;
    while (i < s.size() && (s[i] == L' ' || s[i] == L'\t')) ++i;
    return s.substr(i);
}

void log(const std::wstring& msg) {
    std::wstring line = L"[launcher] " + msg + L"\n";
    DWORD written = 0;
    HANDLE h = GetStdHandle(STD_OUTPUT_HANDLE);
    if (h && h != INVALID_HANDLE_VALUE) {
        WriteConsoleW(h, line.data(), (DWORD)line.size(), &written, nullptr);
    }
    OutputDebugStringW(line.c_str());
}

std::wstring exe_dir() {
    wchar_t buf[MAX_PATH];
    DWORD n = GetModuleFileNameW(nullptr, buf, MAX_PATH);
    std::wstring path(buf, n);
    size_t slash = path.find_last_of(L"\\/");
    if (slash == std::wstring::npos) return L".";
    return path.substr(0, slash);
}

std::wstring path_join(const std::wstring& a, const std::wstring& b) {
    if (a.empty()) return b;
    wchar_t last = a.back();
    if (last == L'\\' || last == L'/') return a + b;
    return a + L"\\" + b;
}

bool file_exists(const std::wstring& path) {
    DWORD attrs = GetFileAttributesW(path.c_str());
    return attrs != INVALID_FILE_ATTRIBUTES && !(attrs & FILE_ATTRIBUTE_DIRECTORY);
}

std::wstring read_file_text(const std::wstring& path) {
    std::ifstream f(path);
    if (!f) return L"";
    std::stringstream ss;
    ss << f.rdbuf();
    return utf8_to_wide(ss.str());
}

bool write_file_text(const std::wstring& path, const std::wstring& contents) {
    std::ofstream f(path, std::ios::binary | std::ios::trunc);
    if (!f) return false;
    std::string utf8 = wide_to_utf8(contents);
    f.write(utf8.data(), (std::streamsize)utf8.size());
    return f.good();
}

bool write_file_bytes(const std::wstring& path, const std::vector<BYTE>& data) {
    std::ofstream f(path, std::ios::binary | std::ios::trunc);
    if (!f) return false;
    if (!data.empty())
        f.write(reinterpret_cast<const char*>(data.data()), (std::streamsize)data.size());
    return f.good();
}

// ---------- WinHTTP helpers ----------

struct HttpResponse {
    DWORD status = 0;
    std::vector<BYTE> body;
};

std::optional<HttpResponse> http_get(const wchar_t* host, const wchar_t* path,
                                     INTERNET_PORT port = INTERNET_DEFAULT_HTTPS_PORT,
                                     bool https = true,
                                     const wchar_t* extra_headers = nullptr) {
    HINTERNET hSession = WinHttpOpen(kUserAgent,
                                     WINHTTP_ACCESS_TYPE_DEFAULT_PROXY,
                                     WINHTTP_NO_PROXY_NAME,
                                     WINHTTP_NO_PROXY_BYPASS, 0);
    if (!hSession) return std::nullopt;

    // Force modern TLS versions.
    DWORD tls_flags = WINHTTP_FLAG_SECURE_PROTOCOL_TLS1_2 | WINHTTP_FLAG_SECURE_PROTOCOL_TLS1_3;
    WinHttpSetOption(hSession, WINHTTP_OPTION_SECURE_PROTOCOLS, &tls_flags, sizeof(tls_flags));

    HINTERNET hConnect = WinHttpConnect(hSession, host, port, 0);
    if (!hConnect) { WinHttpCloseHandle(hSession); return std::nullopt; }

    DWORD flags = https ? WINHTTP_FLAG_SECURE : 0;
    HINTERNET hRequest = WinHttpOpenRequest(hConnect, L"GET", path, nullptr,
                                            WINHTTP_NO_REFERER,
                                            WINHTTP_DEFAULT_ACCEPT_TYPES, flags);
    if (!hRequest) { WinHttpCloseHandle(hConnect); WinHttpCloseHandle(hSession); return std::nullopt; }

    DWORD redir = WINHTTP_OPTION_REDIRECT_POLICY_ALWAYS;
    WinHttpSetOption(hRequest, WINHTTP_OPTION_REDIRECT_POLICY, &redir, sizeof(redir));

    BOOL sent = WinHttpSendRequest(hRequest,
                                   extra_headers ? extra_headers : WINHTTP_NO_ADDITIONAL_HEADERS,
                                   extra_headers ? (DWORD)-1L : 0,
                                   WINHTTP_NO_REQUEST_DATA, 0, 0, 0);
    if (!sent || !WinHttpReceiveResponse(hRequest, nullptr)) {
        WinHttpCloseHandle(hRequest);
        WinHttpCloseHandle(hConnect);
        WinHttpCloseHandle(hSession);
        return std::nullopt;
    }

    HttpResponse resp;
    DWORD status_size = sizeof(resp.status);
    WinHttpQueryHeaders(hRequest,
                        WINHTTP_QUERY_STATUS_CODE | WINHTTP_QUERY_FLAG_NUMBER,
                        WINHTTP_HEADER_NAME_BY_INDEX,
                        &resp.status, &status_size, WINHTTP_NO_HEADER_INDEX);

    for (;;) {
        DWORD avail = 0;
        if (!WinHttpQueryDataAvailable(hRequest, &avail)) break;
        if (avail == 0) break;
        size_t old_size = resp.body.size();
        resp.body.resize(old_size + avail);
        DWORD read = 0;
        if (!WinHttpReadData(hRequest, resp.body.data() + old_size, avail, &read)) break;
        resp.body.resize(old_size + read);
        if (read == 0) break;
    }

    WinHttpCloseHandle(hRequest);
    WinHttpCloseHandle(hConnect);
    WinHttpCloseHandle(hSession);
    return resp;
}

// Split a full URL into host + path. Returns false on malformed input.
bool parse_url(const std::wstring& url, std::wstring& host_out, std::wstring& path_out,
               INTERNET_PORT& port_out, bool& https_out) {
    URL_COMPONENTSW uc;
    ZeroMemory(&uc, sizeof(uc));
    uc.dwStructSize = sizeof(uc);
    uc.dwSchemeLength    = (DWORD)-1;
    uc.dwHostNameLength  = (DWORD)-1;
    uc.dwUrlPathLength   = (DWORD)-1;
    uc.dwExtraInfoLength = (DWORD)-1;
    if (!WinHttpCrackUrl(url.c_str(), (DWORD)url.size(), 0, &uc)) return false;
    host_out.assign(uc.lpszHostName, uc.dwHostNameLength);
    path_out.assign(uc.lpszUrlPath, uc.dwUrlPathLength);
    if (uc.dwExtraInfoLength > 0) path_out.append(uc.lpszExtraInfo, uc.dwExtraInfoLength);
    port_out  = uc.nPort;
    https_out = (uc.nScheme == INTERNET_SCHEME_HTTPS);
    return true;
}

// ---------- crude JSON extraction (we control the producer; no external dep needed) ----------

// Decode a JSON-escaped string. Stops at the closing quote.
// 'pos' starts just after the opening quote and is left pointing at the closing quote.
std::string json_read_string(const std::string& s, size_t& pos) {
    std::string out;
    while (pos < s.size()) {
        char c = s[pos];
        if (c == '"') return out;
        if (c == '\\' && pos + 1 < s.size()) {
            char n = s[pos + 1];
            switch (n) {
                case '"':  out += '"';  break;
                case '\\': out += '\\'; break;
                case '/':  out += '/';  break;
                case 'n':  out += '\n'; break;
                case 'r':  out += '\r'; break;
                case 't':  out += '\t'; break;
                case 'b':  out += '\b'; break;
                case 'f':  out += '\f'; break;
                case 'u':
                    // Skip 4 hex digits — we don't expect non-ASCII in tag names/URLs.
                    if (pos + 5 < s.size()) pos += 4;
                    break;
                default:   out += n;    break;
            }
            pos += 2;
            continue;
        }
        out += c;
        ++pos;
    }
    return out;
}

// Find the first occurrence of "key":"value" and return the value.
std::optional<std::string> json_find_string(const std::string& body, const std::string& key) {
    std::string needle = "\"" + key + "\"";
    size_t pos = 0;
    while ((pos = body.find(needle, pos)) != std::string::npos) {
        pos += needle.size();
        while (pos < body.size() && (body[pos] == ' ' || body[pos] == '\t' || body[pos] == ':' ||
                                     body[pos] == '\r' || body[pos] == '\n')) ++pos;
        if (pos >= body.size() || body[pos] != '"') continue;
        ++pos;
        return json_read_string(body, pos);
    }
    return std::nullopt;
}

// Find an asset with matching `name`, return its `browser_download_url`.
std::optional<std::string> find_asset_url(const std::string& body, const std::string& asset_name) {
    // Walk through every "name":"..." key. When we find one matching asset_name, look
    // ahead for the next "browser_download_url":"...".
    size_t pos = 0;
    while ((pos = body.find("\"name\"", pos)) != std::string::npos) {
        pos += 6;
        while (pos < body.size() && (body[pos] == ' ' || body[pos] == ':' ||
                                     body[pos] == '\r' || body[pos] == '\n' ||
                                     body[pos] == '\t')) ++pos;
        if (pos >= body.size() || body[pos] != '"') continue;
        ++pos;
        std::string name = json_read_string(body, pos);
        if (name == asset_name) {
            // Find next browser_download_url after this point.
            size_t key_at = body.find("\"browser_download_url\"", pos);
            if (key_at == std::string::npos) return std::nullopt;
            key_at += 22;
            while (key_at < body.size() && (body[key_at] == ' ' || body[key_at] == ':' ||
                                            body[key_at] == '\r' || body[key_at] == '\n' ||
                                            body[key_at] == '\t')) ++key_at;
            if (key_at >= body.size() || body[key_at] != '"') return std::nullopt;
            ++key_at;
            return json_read_string(body, key_at);
        }
    }
    return std::nullopt;
}

// ---------- process control ----------

void wait_for_pid(DWORD pid, DWORD timeout_ms) {
    if (pid == 0) return;
    HANDLE h = OpenProcess(SYNCHRONIZE, FALSE, pid);
    if (!h) return;
    WaitForSingleObject(h, timeout_ms);
    CloseHandle(h);
}

bool launch_game(const std::wstring& game_path) {
    STARTUPINFOW si{};
    si.cb = sizeof(si);
    PROCESS_INFORMATION pi{};
    std::wstring cmd = L"\"" + game_path + L"\"";
    std::vector<wchar_t> mutable_cmd(cmd.begin(), cmd.end());
    mutable_cmd.push_back(L'\0');
    BOOL ok = CreateProcessW(game_path.c_str(), mutable_cmd.data(), nullptr, nullptr,
                             FALSE, 0, nullptr, exe_dir().c_str(), &si, &pi);
    if (!ok) return false;
    CloseHandle(pi.hThread);
    CloseHandle(pi.hProcess);
    return true;
}

// ---------- argv parsing ----------

struct Args {
    bool force_update = false;
    DWORD wait_pid = 0;
};

Args parse_args() {
    Args a;
    int argc = 0;
    LPWSTR* argv = CommandLineToArgvW(GetCommandLineW(), &argc);
    if (!argv) return a;
    for (int i = 1; i < argc; ++i) {
        std::wstring s = argv[i];
        if (s == L"--update" || s == L"-u") {
            a.force_update = true;
        } else if (s == L"--wait-pid" && i + 1 < argc) {
            a.wait_pid = (DWORD)_wtoi(argv[++i]);
        }
    }
    LocalFree(argv);
    return a;
}

// ---------- update flow ----------

bool check_and_update(const std::wstring& dir, bool /*forced*/) {
    std::wstring api_path = std::wstring(L"/repos/") + kRepoOwner + L"/" + kRepoName + L"/releases/latest";
    log(L"Checking " + std::wstring(kApiHost) + api_path);

    // GitHub requires Accept header in some cases; harmless when not.
    auto resp = http_get(kApiHost, api_path.c_str(),
                        INTERNET_DEFAULT_HTTPS_PORT, true,
                        L"Accept: application/vnd.github+json\r\n");
    if (!resp) {
        log(L"No network or HTTP error. Skipping update.");
        return false;
    }
    if (resp->status == 404) {
        log(L"No release published yet. Skipping update.");
        return false;
    }
    if (resp->status != 200) {
        wchar_t buf[64];
        wsprintfW(buf, L"GitHub API returned status %lu. Skipping update.", resp->status);
        log(buf);
        return false;
    }

    std::string body(reinterpret_cast<const char*>(resp->body.data()), resp->body.size());

    auto tag_opt = json_find_string(body, "tag_name");
    if (!tag_opt) {
        log(L"Could not parse tag_name. Skipping update.");
        return false;
    }
    std::wstring remote_tag = utf8_to_wide(*tag_opt);
    log(L"Remote tag: " + remote_tag);

    std::wstring version_path = path_join(dir, kVersionFile);
    std::wstring local_version = trim(read_file_text(version_path));
    if (local_version.empty()) local_version = L"v0.0.0";
    log(L"Local version: " + local_version);

    if (local_version == remote_tag) {
        log(L"Up to date.");
        return true;
    }

    auto url_opt = find_asset_url(body, wide_to_utf8(kAssetName));
    if (!url_opt) {
        log(L"Could not find game.exe asset in release. Skipping.");
        return false;
    }
    std::wstring asset_url = utf8_to_wide(*url_opt);
    log(L"Downloading " + asset_url);

    std::wstring host, path;
    INTERNET_PORT port = 0;
    bool https = true;
    if (!parse_url(asset_url, host, path, port, https)) {
        log(L"Bad asset URL.");
        return false;
    }
    auto dl = http_get(host.c_str(), path.c_str(), port, https, nullptr);
    if (!dl || dl->status != 200 || dl->body.empty()) {
        log(L"Download failed.");
        return false;
    }

    std::wstring tmp_path = path_join(dir, L"game.exe.new");
    if (!write_file_bytes(tmp_path, dl->body)) {
        log(L"Could not write " + tmp_path);
        return false;
    }

    std::wstring game_path = path_join(dir, kGameExe);
    // Replace atomically. If the target doesn't yet exist, MOVEFILE_REPLACE_EXISTING is a no-op.
    if (!MoveFileExW(tmp_path.c_str(), game_path.c_str(),
                     MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH)) {
        DWORD err = GetLastError();
        wchar_t buf[128];
        wsprintfW(buf, L"MoveFileEx failed (%lu). Retry next launch.", err);
        log(buf);
        return false;
    }

    if (!write_file_text(version_path, remote_tag + L"\n")) {
        log(L"Warning: could not write version.txt");
    }
    log(L"Updated to " + remote_tag);
    return true;
}

} // namespace

int wmain() {
    SetConsoleOutputCP(CP_UTF8);

    Args args = parse_args();
    if (args.wait_pid != 0) {
        log(L"Waiting for game (pid=" + std::to_wstring(args.wait_pid) + L") to exit...");
        wait_for_pid(args.wait_pid, 15000);
        // Small grace period for the OS to release the file handle.
        Sleep(300);
    }

    std::wstring dir = exe_dir();
    std::wstring game_path = path_join(dir, kGameExe);

    check_and_update(dir, args.force_update);

    if (!file_exists(game_path)) {
        log(L"game.exe not found at " + game_path);
        log(L"Make sure the launcher sits next to game.exe.");
        return 1;
    }

    log(L"Launching " + game_path);
    if (!launch_game(game_path)) {
        log(L"Failed to launch game.exe");
        return 1;
    }
    return 0;
}

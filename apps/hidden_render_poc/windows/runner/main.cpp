#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include <charconv>
#include <cstdint>
#include <limits>

#include "flutter_window.h"
#include "utils.h"

namespace {
bool ParseBytes(const std::string& text, uint64_t* value) {
  const auto parsed = std::from_chars(text.data(), text.data() + text.size(), *value);
  return parsed.ec == std::errc() && parsed.ptr == text.data() + text.size();
}

// A short-lived worker joins a job before creating the Flutter engine, so its
// process commit limit applies during initialization as well as rendering.
HANDLE ConfigureWorkerMemoryLimit(const std::string& text) {
  uint64_t limit = 0;
  if (!ParseBytes(text, &limit) || limit < 67108864 ||
      limit > std::numeric_limits<SIZE_T>::max()) {
    return nullptr;
  }
  HANDLE job = ::CreateJobObjectW(nullptr, nullptr);
  if (!job) return nullptr;
  JOBOBJECT_EXTENDED_LIMIT_INFORMATION info{};
  info.BasicLimitInformation.LimitFlags = JOB_OBJECT_LIMIT_PROCESS_MEMORY;
  info.ProcessMemoryLimit = static_cast<SIZE_T>(limit);
  if (!::SetInformationJobObject(job, JobObjectExtendedLimitInformation,
                                  &info, sizeof(info)) ||
      !::AssignProcessToJobObject(job, ::GetCurrentProcess())) {
    ::CloseHandle(job);
    return nullptr;
  }
  JOBOBJECT_EXTENDED_LIMIT_INFORMATION actual{};
  if (!::QueryInformationJobObject(job, JobObjectExtendedLimitInformation,
                                    &actual, sizeof(actual), nullptr) ||
      (actual.BasicLimitInformation.LimitFlags & JOB_OBJECT_LIMIT_PROCESS_MEMORY) == 0 ||
      actual.ProcessMemoryLimit != info.ProcessMemoryLimit) {
    ::CloseHandle(job);
    return nullptr;
  }
  return job;
}
}  // namespace

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  HANDLE memory_job = nullptr;
  if (!command_line_arguments.empty() &&
      command_line_arguments[0] == "--memory-limit-probe") {
    if (command_line_arguments.size() != 4 ||
        (command_line_arguments[3] != "fail" && command_line_arguments[3] != "succeed")) {
      return EXIT_FAILURE;
    }
    memory_job = ConfigureWorkerMemoryLimit(command_line_arguments[1]);
    uint64_t allocation = 0;
    if (!memory_job || !ParseBytes(command_line_arguments[2], &allocation) ||
        allocation == 0 || allocation > std::numeric_limits<SIZE_T>::max()) {
      if (memory_job) ::CloseHandle(memory_job);
      return EXIT_FAILURE;
    }
    void* memory = ::VirtualAlloc(nullptr, static_cast<SIZE_T>(allocation),
                                  MEM_RESERVE | MEM_COMMIT, PAGE_READWRITE);
    if (memory) ::VirtualFree(memory, 0, MEM_RELEASE);
    ::CloseHandle(memory_job);
    const bool expected_success = command_line_arguments[3] == "succeed";
    return ((memory != nullptr) == expected_success) ? EXIT_SUCCESS : EXIT_FAILURE;
  }
  if (!command_line_arguments.empty() &&
      command_line_arguments[0] == "--render-snapshot-worker") {
    ::SetErrorMode(SEM_FAILCRITICALERRORS | SEM_NOGPFAULTERRORBOX);
    if (command_line_arguments.size() != 5) return EXIT_FAILURE;
    memory_job = ConfigureWorkerMemoryLimit(command_line_arguments[4]);
    if (!memory_job) return EXIT_FAILURE;
  }

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  if (!window.Create(L"fflow_hidden_render_poc", origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  if (memory_job) ::CloseHandle(memory_job);
  return EXIT_SUCCESS;
}

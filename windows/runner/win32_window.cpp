#include "win32_window.h"
#include <flutter_windows.h>
#include "resource.h"
namespace {
int Scale(int source, double scale_factor) { return static_cast<int>(source * scale_factor); }
constexpr wchar_t kWindowClassName[] = L"FLUTTER_RUNNER_WIN32_WINDOW";
const wchar_t* kWindowTitle = L"THAMAN POS";
class WindowClassRegistrar {
 public:
  ~WindowClassRegistrar(){ if (class_registered_) UnregisterClass(kWindowClassName, nullptr); }
  static WindowClassRegistrar* GetInstance(){ static WindowClassRegistrar instance; return &instance; }
  const wchar_t* GetWindowClass(){
    if (!class_registered_) {
      WNDCLASS window_class{};
      window_class.hCursor = LoadCursor(nullptr, IDC_ARROW);
      window_class.lpszClassName = kWindowClassName;
      window_class.style = CS_HREDRAW | CS_VREDRAW;
      window_class.cbClsExtra = 0; window_class.cbWndExtra = 0;
      window_class.hInstance = GetModuleHandle(nullptr);
      window_class.hIcon = LoadIcon(window_class.hInstance, MAKEINTRESOURCE(IDI_APP_ICON));
      window_class.hbrBackground = nullptr;
      window_class.lpszMenuName = nullptr;
      window_class.lpfnWndProc = Win32Window::WndProc;
      RegisterClass(&window_class); class_registered_ = true;
    }
    return kWindowClassName;
  }
 private: bool class_registered_ = false;
};
}
Win32Window::Win32Window() {}
Win32Window::~Win32Window(){ Destroy(); }
bool Win32Window::Create(const std::wstring& title, const Point& origin, const Size& size) {
  Destroy();
  const wchar_t* window_class = WindowClassRegistrar::GetInstance()->GetWindowClass();
  const POINT target_point = {static_cast<LONG>(origin.x), static_cast<LONG>(origin.y)};
  HMONITOR monitor = MonitorFromPoint(target_point, MONITOR_DEFAULTTONEAREST);
  UINT dpi = FlutterDesktopGetDpiForMonitor(monitor);
  double scale_factor = dpi / 96.0;
  HWND window = CreateWindow(window_class, title.c_str(), WS_OVERLAPPEDWINDOW,
    Scale(origin.x, scale_factor), Scale(origin.y, scale_factor), Scale(size.width, scale_factor), Scale(size.height, scale_factor),
    nullptr, nullptr, GetModuleHandle(nullptr), this);
  if (!window) return false;
  return OnCreate();
}
bool Win32Window::Show(){ return ShowWindow(window_handle_, SW_SHOWNORMAL); }
void Win32Window::Destroy(){ if (window_handle_) { DestroyWindow(window_handle_); window_handle_ = nullptr; } }
void Win32Window::SetChildContent(HWND content){
  child_content_ = content; SetParent(content, window_handle_); RECT frame = GetClientArea(); MoveWindow(content, frame.left, frame.top, frame.right-frame.left, frame.bottom-frame.top, true); SetFocus(child_content_);
}
RECT Win32Window::GetClientArea(){ RECT frame; GetClientRect(window_handle_, &frame); return frame; }
void Win32Window::SetQuitOnClose(bool quit_on_close){ quit_on_close_ = quit_on_close; }
bool Win32Window::OnCreate(){ return true; }
void Win32Window::OnDestroy() {}
LRESULT Win32Window::MessageHandler(HWND hwnd, UINT const message, WPARAM const wparam, LPARAM const lparam) noexcept {
  switch(message){
    case WM_DESTROY: window_handle_ = nullptr; OnDestroy(); if (quit_on_close_) PostQuitMessage(0); return 0;
    case WM_DPICHANGED: { auto newRect = reinterpret_cast<RECT*>(lparam); LONG width = newRect->right-newRect->left, height=newRect->bottom-newRect->top; SetWindowPos(hwnd,nullptr,newRect->left,newRect->top,width,height,SWP_NOZORDER|SWP_NOACTIVATE); return 0; }
    case WM_SIZE: if (child_content_) { RECT rect=GetClientArea(); MoveWindow(child_content_, rect.left, rect.top, rect.right-rect.left, rect.bottom-rect.top, TRUE); } return 0;
    case WM_ACTIVATE: if (child_content_) SetFocus(child_content_); return 0;
  }
  return DefWindowProc(window_handle_, message, wparam, lparam);
}
Win32Window* Win32Window::GetThisFromHandle(HWND const window) noexcept { return reinterpret_cast<Win32Window*>(GetWindowLongPtr(window, GWLP_USERDATA)); }
LRESULT CALLBACK Win32Window::WndProc(HWND const window, UINT const message, WPARAM const wparam, LPARAM const lparam) noexcept {
  if (message == WM_NCCREATE) {
    auto window_struct = reinterpret_cast<CREATESTRUCT*>(lparam);
    SetWindowLongPtr(window, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(window_struct->lpCreateParams));
    auto that = static_cast<Win32Window*>(window_struct->lpCreateParams); that->window_handle_ = window;
  } else if (auto that = GetThisFromHandle(window)) {
    return that->MessageHandler(window, message, wparam, lparam);
  }
  return DefWindowProc(window, message, wparam, lparam);
}

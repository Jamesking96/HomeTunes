// The smallest the HomeTunes window can be made on Windows (0.1.72, the user's request: "ensure
// there is a minimum window size set & tell me where it is so that I can modify it later").
//
// Change these two numbers to change the limit. They're the whole window (title bar and edges
// included), in the same units as Windows' display settings at 100 % scale: at 150 % the window
// is held at 1.5 times as many pixels, so it looks the same size on any screen.
//
// At this size the app still works: it draws itself a little smaller (Settings › Appearance ›
// Shrink to fit small windows), Now Playing hides the cover and shrinks its buttons, and a
// music video takes the whole page with its buttons over the picture.
//
// Used by Win32Window::MessageHandler (win32_window.cpp, WM_GETMINMAXINFO). Rebuild the app
// after changing them.
#ifndef RUNNER_WINDOW_LIMITS_H_
#define RUNNER_WINDOW_LIMITS_H_

constexpr int kMinWindowWidth = 480;
constexpr int kMinWindowHeight = 420;

#endif  // RUNNER_WINDOW_LIMITS_H_

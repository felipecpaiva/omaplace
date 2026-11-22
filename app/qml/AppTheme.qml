import QtQuick
// Copied from omadials-settings (MIT, same author).
import "Contrast.js" as Contrast
// The app's colours come from the current Omarchy theme (colors.toml) and follow a theme switch live. Lines, fills and
// help text are the theme's text colour at a low opacity, so they keep contrast in every theme (validated 2026-11-17
// over all installed themes). The literals are only fallbacks for a theme file that lacks a key.
QtObject {
    readonly property var c: desktopTheme.colors || ({})
    function pick(key, fallback) { return c[key] !== undefined ? c[key] : fallback }
    function fade(color, amount) { return Qt.rgba(color.r, color.g, color.b, amount) }
    readonly property bool light: Contrast.isLight(String(background))
    property color background: pick("background", "#0e0e10")
    // Light themes name their card colour dark_background; dark themes lighter_background.
    property color surface: light ? pick("dark_background", background) : pick("lighter_background", background)
    property color text: pick("bright_foreground", pick("foreground", "#eeeeee"))
    property color secondary: fade(text, 0.72)
    property color warn: pick("red", "#ffb86c")
    property color off: fade(text, 0.10)
    property color edge: fade(text, 0.30)
    property color track: fade(text, 0.25)
    property color clear: "transparent"
    // A weak accent (under 3:1 on the cards, as on white or rose-pine) falls back to the text colour, like the plugin.
    readonly property bool accentOk: Contrast.ratio(String(desktopTheme.accent), String(surface)) >= 3
    property color accent: accentOk ? desktopTheme.accent : text
    property color ink: accentOk ? desktopTheme.accentForeground : surface
    property int radius: desktopTheme.radius
    property string font: "sans-serif"
}

package io.github.ilinmu.via.ui

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color

private val LightColors = lightColorScheme(
    primary = Color(0xFF0A84FF),
    onPrimary = Color.White,
    background = Color(0xFFF6F6F8),
    surface = Color(0xFFF6F6F8),
    surfaceVariant = Color(0xFFFFFFFF),
    onSurfaceVariant = Color(0xFF3C3C43),
    outlineVariant = Color(0xFFE2E2E7),
)

private val DarkColors = darkColorScheme(
    primary = Color(0xFF0A84FF),
    onPrimary = Color.White,
    background = Color(0xFF101012),
    surface = Color(0xFF101012),
    surfaceVariant = Color(0xFF1C1C1E),
    onSurfaceVariant = Color(0xFFB8B8BE),
    outlineVariant = Color(0xFF2C2C2E),
)

@Composable
fun ViaTheme(content: @Composable () -> Unit) {
    MaterialTheme(
        colorScheme = if (isSystemInDarkTheme()) DarkColors else LightColors,
        content = content,
    )
}

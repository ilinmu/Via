package io.github.ilinmu.via.ui

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Typography
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.sp

// One accent (a muted bamboo green) and warm neutrals. Amber only marks a
// state that needs attention; red only marks a real error.
private val LightColors = lightColorScheme(
    primary = Color(0xFF2E6B5C),
    onPrimary = Color.White,
    primaryContainer = Color(0xFFDDEBE5),
    onPrimaryContainer = Color(0xFF143A31),
    secondary = Color(0xFF6B5F45),
    onSecondary = Color.White,
    secondaryContainer = Color(0xFFF1E5CE),
    onSecondaryContainer = Color(0xFF4A3A18),
    tertiary = Color(0xFFA15C00),
    onTertiary = Color.White,
    tertiaryContainer = Color(0xFFF6E3CC),
    onTertiaryContainer = Color(0xFF4A2A00),
    background = Color(0xFFF7F5F1),
    onBackground = Color(0xFF1F1D1A),
    surface = Color(0xFFF7F5F1),
    onSurface = Color(0xFF1F1D1A),
    surfaceVariant = Color(0xFFFFFFFF),
    onSurfaceVariant = Color(0xFF726D65),
    outline = Color(0xFFA8A199),
    outlineVariant = Color(0xFFE4DFD7),
    error = Color(0xFFA33A32),
    onError = Color.White,
    errorContainer = Color(0xFFF3DAD5),
    onErrorContainer = Color(0xFF5A1712),
)

private val DarkColors = darkColorScheme(
    primary = Color(0xFF3C7D6C),
    onPrimary = Color.White,
    primaryContainer = Color(0xFF1E3A32),
    onPrimaryContainer = Color(0xFFB9D8CE),
    secondary = Color(0xFFD8C7A5),
    onSecondary = Color(0xFF332B18),
    secondaryContainer = Color(0xFF43391F),
    onSecondaryContainer = Color(0xFFF1E5CE),
    tertiary = Color(0xFFE0A458),
    onTertiary = Color(0xFF3A2200),
    tertiaryContainer = Color(0xFF4A2F12),
    onTertiaryContainer = Color(0xFFF6DDBD),
    background = Color(0xFF1B1A18),
    onBackground = Color(0xFFF2EEE8),
    surface = Color(0xFF1B1A18),
    onSurface = Color(0xFFF2EEE8),
    surfaceVariant = Color(0xFF232120),
    onSurfaceVariant = Color(0xFFA8A29A),
    outline = Color(0xFF7A756D),
    outlineVariant = Color(0xFF3A3733),
    error = Color(0xFFE58C82),
    onError = Color(0xFF3B0A06),
    errorContainer = Color(0xFF4A211D),
    onErrorContainer = Color(0xFFF6D5D0),
)

// Three text sizes: 22 for a page's subject, 14 for body and controls, 12 for
// supporting text. Weight carries the remaining hierarchy.
private val ViaTypography = Typography(
    headlineSmall = TextStyle(fontSize = 22.sp, lineHeight = 30.sp, fontWeight = FontWeight.SemiBold),
    titleLarge = TextStyle(fontSize = 22.sp, lineHeight = 30.sp, fontWeight = FontWeight.SemiBold),
    titleMedium = TextStyle(fontSize = 14.sp, lineHeight = 20.sp, fontWeight = FontWeight.SemiBold),
    titleSmall = TextStyle(fontSize = 14.sp, lineHeight = 20.sp, fontWeight = FontWeight.SemiBold),
    bodyLarge = TextStyle(fontSize = 14.sp, lineHeight = 22.sp),
    bodyMedium = TextStyle(fontSize = 14.sp, lineHeight = 22.sp),
    bodySmall = TextStyle(fontSize = 12.sp, lineHeight = 18.sp),
    labelLarge = TextStyle(fontSize = 14.sp, lineHeight = 20.sp, fontWeight = FontWeight.Medium),
    labelMedium = TextStyle(fontSize = 12.sp, lineHeight = 16.sp, fontWeight = FontWeight.Medium),
    labelSmall = TextStyle(fontSize = 12.sp, lineHeight = 16.sp),
)

@Composable
fun ViaTheme(content: @Composable () -> Unit) {
    MaterialTheme(
        colorScheme = if (isSystemInDarkTheme()) DarkColors else LightColors,
        typography = ViaTypography,
        content = content,
    )
}

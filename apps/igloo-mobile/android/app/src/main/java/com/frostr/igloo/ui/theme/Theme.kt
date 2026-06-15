// Igloo Design Tokens - derived from igloo-paper design-system/tokens/
// This file is generated from tokens.css / colors.json / typography.json
// and should be re-generated when tokens change. It is NOT imported from
// repos/igloo-paper directly (reference-only, one-way codegen).

package com.frostr.igloo.ui.theme

import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.sp

// MARK: - Colors

object IglooColors {
    // Background
    val Gray950 = Color(0xFF030712)
    val Gray900 = Color(0xFF111827)
    val Gray900Translucent = Color(0x66111827)  // 40% alpha
    val Slate900Translucent = Color(0x990F172A)  // 60% alpha
    val Slate900StrongTranslucent = Color(0xCC0F172A)  // 80% alpha

    // Blue Scale - Primary
    val Blue100 = Color(0xFFDBEAFE)
    val Blue200 = Color(0xFFBFDBFE)
    val Blue300 = Color(0xFF93C5FD)
    val Blue400 = Color(0xFF60A5FA)
    val Blue600 = Color(0xFF2563EB)
    val Blue700 = Color(0xFF1D4ED8)
    val Blue900 = Color(0xFF1E3A8A)

    // Semantic
    val Green600 = Color(0xFF16A34A)
    val Green900 = Color(0xFF14532D)
    val Red400 = Color(0xFFF87171)
    val Red600 = Color(0xFFDC2626)
    val Amber400 = Color(0xFFFBBF24)
    val Orange400 = Color(0xFFFB923C)
    val Purple400 = Color(0xFFC084FC)
    val Purple900 = Color(0xFF581C87)
    val Red900Translucent = Color(0x4D7F1D1D)  // 30% alpha
    val Yellow900Translucent = Color(0x4D713F12)  // 30% alpha

    // Interface Text
    val Slate200 = Color(0xFFE2E8F0)
    val Slate400 = Color(0xFF94A3B8)
    val Slate500 = Color(0xFF64748B)

    // Interface Borders & Overlays
    val Blue900FocusBorder = Color(0x4D1E3A8A)  // 30% alpha
    val Blue900PanelBorder = Color(0x331E3A8A)  // 20% alpha
    val Slate400MutedBorder = Color(0x3394A3B8)  // 20% alpha
    val Red500DestructiveBg = Color(0x0FEF4444)  // 6% alpha
    val Red500DestructiveBorder = Color(0x4DEF4444)  // 30% alpha

    // Status
    val StatusDefault = Color(0xFF6B7280)
    val StatusSuccess = Color(0xFF22C55E)
    val StatusError = Color(0xFFEF4444)
    val StatusWarning = Color(0xFFEAB308)
    val StatusInfo = Color(0xFF3B82F6)
}

// MARK: - Typography

// Custom font families bundled in res/font/
private val ShareTechMono = FontFamily.Monospace

private val Inter = FontFamily.SansSerif

object IglooTypography {
    // H1 Heading - Share Tech Mono 36px regular
    val h1: TextStyle = TextStyle(
        fontFamily = ShareTechMono,
        fontSize = 36.sp,
        lineHeight = 44.sp,
        letterSpacing = (-0.01).sp,
        fontWeight = FontWeight.Normal
    )

    // H2 Section Header - Share Tech Mono 24px regular
    val h2: TextStyle = TextStyle(
        fontFamily = ShareTechMono,
        fontSize = 24.sp,
        lineHeight = 30.sp,
        fontWeight = FontWeight.Normal
    )

    // H3 Card Title - Share Tech Mono 20px regular
    val h3: TextStyle = TextStyle(
        fontFamily = ShareTechMono,
        fontSize = 20.sp,
        lineHeight = 24.sp,
        fontWeight = FontWeight.Normal
    )

    // Body text - Inter 14px regular
    val body: TextStyle = TextStyle(
        fontFamily = Inter,
        fontSize = 14.sp,
        lineHeight = 18.sp,
        fontWeight = FontWeight.Normal
    )

    // Small - Inter 12px regular
    val small: TextStyle = TextStyle(
        fontFamily = Inter,
        fontSize = 12.sp,
        lineHeight = 16.sp,
        fontWeight = FontWeight.Normal
    )

    val label: TextStyle = TextStyle(
        fontFamily = Inter,
        fontSize = 12.sp,
        lineHeight = 16.sp,
        fontWeight = FontWeight.Medium
    )

    // Value data - Share Tech Mono 14px regular
    val valueData: TextStyle = TextStyle(
        fontFamily = ShareTechMono,
        fontSize = 14.sp,
        lineHeight = 18.sp,
        fontWeight = FontWeight.Normal
    )

    // Mono labels - Inter 12px regular (medium weight for slight emphasis)
    val monoLabel: TextStyle = TextStyle(
        fontFamily = Inter,
        fontSize = 12.sp,
        lineHeight = 16.sp,
        fontWeight = FontWeight.Medium
    )
}

// MARK: - Spacing & Radii

object IglooSpacing {
    val xs: Float = 4f
    val sm: Float = 8f
    val md: Float = 16f
    val lg: Float = 24f
    val xl: Float = 32f
    val xxl: Float = 48f
}

object IglooRadii {
    val sm: Float = 8f
    val md: Float = 12f
    val lg: Float = 16f
    val xl: Float = 18f
    val full: Float = 9999f
}

// MARK: - Theme data class

data class IglooTheme(
    val background: Color = IglooColors.Gray950,
    val surfacePanel: Color = IglooColors.Slate900StrongTranslucent,
    val surfaceCard: Color = IglooColors.Gray900Translucent,
    val border: Color = IglooColors.Blue900PanelBorder,
    val borderFocused: Color = IglooColors.Blue900FocusBorder,
    val primary: Color = IglooColors.Blue600,
    val primaryAccent: Color = IglooColors.Blue400,
    val textPrimary: Color = IglooColors.Slate200,
    val textSecondary: Color = IglooColors.Slate400,
    val textMuted: Color = IglooColors.Slate500
)

// MARK: - Material3 Theme

private val IglooDarkColors = darkColorScheme(
    primary = IglooColors.Blue600,
    onPrimary = IglooColors.Slate200,
    primaryContainer = IglooColors.Blue900,
    onPrimaryContainer = IglooColors.Blue100,
    secondary = IglooColors.Slate400,
    onSecondary = IglooColors.Slate200,
    secondaryContainer = IglooColors.Slate900StrongTranslucent,
    onSecondaryContainer = IglooColors.Slate200,
    tertiary = IglooColors.Blue400,
    onTertiary = IglooColors.Gray950,
    background = IglooColors.Gray950,
    onBackground = IglooColors.Slate200,
    surface = IglooColors.Slate900StrongTranslucent,
    onSurface = IglooColors.Slate200,
    surfaceVariant = IglooColors.Gray900Translucent,
    onSurfaceVariant = IglooColors.Slate400,
    error = IglooColors.Red600,
    onError = IglooColors.Slate200,
    outline = IglooColors.Blue900PanelBorder,
    outlineVariant = IglooColors.Slate400MutedBorder
)

@Composable
fun AppTheme(content: @Composable () -> Unit) {
    MaterialTheme(
        colorScheme = IglooDarkColors,
        content = content,
    )
}

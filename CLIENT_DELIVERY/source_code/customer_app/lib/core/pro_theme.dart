import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class ProTheme {
  // 🎨 Multi-Color Brand Palette (Differentiated from Zomato)
  // Incorporating Orange, Yellow, and Green as requested
  
  static const Color primary = Color(0xFFFF6D00); // 🟠 Vibrant Orange (Main Action)
  static const Color secondary = Color(0xFF2E7D32); // 🟢 Deep Green (Trust & Veg)
  static const Color highlight = Color(0xFFFFC107); // 🟡 Amber/Yellow (Offers & Highlights)
  
  static const Color accent = Color(0xFFFFF3E0); // Light orange background tint
  static const Color bg = Colors.white; 
  static const Color surface = Colors.white; 
  static const Color dark = Color(0xFF1A1A1A); // Clean black for text
  static const Color gray = Color(0xFFA4B0BE);
  static const Color success = Color(0xFF2ED573);
  static const Color error = Color(0xFFFF5252);
  static const Color white = Colors.white;

  // Backwards compatibility aliases
  static List<BoxShadow> get shadow => softShadow;

  // 🌈 Multi-Color Gradient (Orange to Yellow)
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [Color(0xFFFF6D00), Color(0xFFFFB300)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient successGradient = LinearGradient(
    colors: [Color(0xFF2E7D32), Color(0xFF43A047)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // ✒️ Typography
  static TextStyle get header => GoogleFonts.outfit(
        fontSize: 28,
        fontWeight: FontWeight.w900,
        color: dark,
        letterSpacing: -0.5,
      );

  static TextStyle get title => GoogleFonts.outfit(
        fontSize: 18,
        fontWeight: FontWeight.w700,
        color: dark,
      );

  static TextStyle get body => GoogleFonts.inter(
        fontSize: 14,
        fontWeight: FontWeight.w400,
        color: const Color(0xFF57606F),
        height: 1.5,
      );

  static TextStyle get label => GoogleFonts.outfit(
        fontSize: 12,
        fontWeight: FontWeight.w900,
        color: dark,
        letterSpacing: 1.5,
      );

  static TextStyle get button => GoogleFonts.outfit(
        fontSize: 16,
        fontWeight: FontWeight.w700,
        color: Colors.white,
        letterSpacing: 0.5,
      );

  // 🖼️ Shadows
  static List<BoxShadow> get softShadow => [
        BoxShadow(
          color: Colors.black.withOpacity(0.04),
          blurRadius: 20,
          offset: const Offset(0, 8),
        ),
      ];

  // 🧊 Input Decorations
  static InputDecoration inputDecor(String hint, IconData icon) {
    return InputDecoration(
      hintText: hint,
      hintStyle: body.copyWith(color: gray),
      prefixIcon: Icon(icon, color: primary.withOpacity(0.7)),
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(vertical: 18, horizontal: 20),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: Colors.grey[200]!),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: Colors.grey[100]!),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: primary, width: 2),
      ),
    );
  }

  // 🔘 Button Styles
  static ButtonStyle get ctaButton => ElevatedButton.styleFrom(
        backgroundColor: primary,
        foregroundColor: Colors.white,
        shadowColor: primary.withOpacity(0.3),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        padding: const EdgeInsets.symmetric(vertical: 16),
        elevation: 4,
      );
}

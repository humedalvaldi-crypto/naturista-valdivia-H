import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// Logotipo del proyecto "Vivir entre Humedales" (Proyecto Explora 25-26),
/// dentro de un disco blanco para que se lea bien sobre fondos oscuros
/// (pantalla 1 "Splash" de la lámina). [color] es el color del borde.
class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 96, this.color = AppColors.gold});

  static const asset = 'assets/branding/logo_vivir_entre_humedales.jpg';

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      image: true,
      label: 'Vivir entre Humedales — Proyecto Explora 25-26',
      child: Container(
        width: size,
        height: size,
        padding: EdgeInsets.all(size * 0.02),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white,
          border: Border.all(color: color, width: size * 0.025),
        ),
        child: ClipOval(
          child: Image.asset(
            asset,
            fit: BoxFit.cover,
            errorBuilder: (context, _, _) => Icon(Icons.eco, color: color, size: size * 0.5),
          ),
        ),
      ),
    );
  }
}

/// Pegatinas de la rana del proyecto (assets/stickers) usadas en los
/// estados especiales (sección 15 de la lámina).
enum FrogSticker {
  neutral('assets/stickers/1.png'),
  running('assets/stickers/ilustracion_20260817_4_1.png'),
  surprised('assets/stickers/ilustracion_20260817_4_2.png'),
  tired('assets/stickers/ilustracion_20260817_4_3.png'),
  crying('assets/stickers/ilustracion_20260817_4_4.png'),
  idea('assets/stickers/ilustracion_20260817_4_5.png');

  const FrogSticker(this.asset);
  final String asset;
}

class FrogImage extends StatelessWidget {
  const FrogImage(this.sticker, {super.key, this.size = 120});

  final FrogSticker sticker;
  final double size;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: Image.asset(
        sticker.asset,
        height: size,
        fit: BoxFit.contain,
        errorBuilder: (context, _, _) => SizedBox(height: size),
      ),
    );
  }
}

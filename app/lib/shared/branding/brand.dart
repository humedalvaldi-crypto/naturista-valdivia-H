import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// Marca provisional: anillo dorado con hoja, sobre verde oscuro (ver lámina,
/// pantalla 1 "Splash"). Reemplazar por el logotipo definitivo cuando exista
/// como archivo (SVG/PNG) en assets/.
class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 96, this.color = AppColors.gold});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: color, width: size * 0.04),
      ),
      alignment: Alignment.center,
      child: Icon(Icons.eco, color: color, size: size * 0.55, semanticLabel: 'Naturista Valdivia'),
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

class AppAssets {
  AppAssets._();

  // Tightly-cropped wordmark (the source PNG had ~40% empty margin which made
  // it render tiny). Trimmed to the content bounds so it shows large. Used as
  // the in-app "app logo".
  static const logo = 'assets/images/vistar_logo_trimmed.png';

  // The standalone brand symbol (the "S" swoosh) — used for the browser tab,
  // PWA / native launcher icons, and available in-app via
  // `BrandLogo(wordmark: false)`.
  static const logoSymbol = 'assets/images/logo-symbol.png';
}

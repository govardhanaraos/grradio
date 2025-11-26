import 'dart:io' show Platform; // Import dart:io to check the platform

import 'package:google_mobile_ads/google_mobile_ads.dart';

class InterstitialAdManager {
  InterstitialAd? _interstitialAd;
  bool _isAdLoaded = false;

  String get _adUnitId {
    if (Platform.isAndroid) {
      return 'ca-app-pub-3940256099942544/6300978111'; // Android Test Banner ID
    } else if (Platform.isIOS) {
      return 'ca-app-pub-3940256099942544/2934735716'; // iOS Test Banner ID
    }
    // Fallback in case of unsupported platform
    throw UnsupportedError("Unsupported platform");
  }

  void loadInterstitialAd() {
    InterstitialAd.load(
      adUnitId: _adUnitId,
      request: AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (InterstitialAd ad) {
          _interstitialAd = ad;
          _isAdLoaded = true;
          _setupAdListeners();
        },
        onAdFailedToLoad: (LoadAdError error) {
          print('Interstitial ad failed to load: $error');
        },
      ),
    );
  }

  void _setupAdListeners() {
    _interstitialAd?.fullScreenContentCallback = FullScreenContentCallback(
      onAdShowedFullScreenContent: (InterstitialAd ad) {
        print('Ad showed full screen content.');
      },
      onAdDismissedFullScreenContent: (InterstitialAd ad) {
        print('Ad dismissed full screen content.');
        ad.dispose();
        loadInterstitialAd(); // Load next ad
      },
      onAdFailedToShowFullScreenContent: (InterstitialAd ad, AdError error) {
        print('Ad failed to show full screen content: $error');
        ad.dispose();
        loadInterstitialAd();
      },
    );
  }

  void showInterstitialAd() {
    if (_isAdLoaded) {
      _interstitialAd?.show();
      _isAdLoaded = false;
    }
  }

  void dispose() {
    _interstitialAd?.dispose();
  }
}

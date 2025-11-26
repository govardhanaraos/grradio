import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

class BannerAdWidget extends StatefulWidget {
  const BannerAdWidget({Key? key}) : super(key: key);

  @override
  State<BannerAdWidget> createState() => _BannerAdWidgetState();
}

class _BannerAdWidgetState extends State<BannerAdWidget> {
  BannerAd? _bannerAd;
  bool _isAdLoaded = false;
  // 💡 CORRECTED: Define a getter to select the correct test ID string
  String get _adUnitId {
    if (Platform.isAndroid) {
      return 'ca-app-pub-3940256099942544/6300978111'; // Android Test Banner ID
    } else if (Platform.isIOS) {
      return 'ca-app-pub-3940256099942544/2934735716'; // iOS Test Banner ID
    }
    // Fallback in case of unsupported platform
    throw UnsupportedError("Unsupported platform");
  }

  @override
  void initState() {
    super.initState();
    _loadAd();
  }

  // Load an Anchored Adaptive Banner Ad
  void _loadAd() async {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) {
        return;
      }

      final adSize =
          await AdSize.getCurrentOrientationAnchoredAdaptiveBannerAdSize(
            MediaQuery.sizeOf(context).width.toInt(),
          );

      if (adSize == null) {
        return; // Could not get ad size.
      }

      _bannerAd = BannerAd(
        adUnitId: _adUnitId,
        request: const AdRequest(),
        size: adSize,
        listener: BannerAdListener(
          onAdLoaded: (Ad ad) {
            print('✅ Banner Ad Loaded Successfully for MP3 Screen');
            if (!mounted) {
              ad.dispose();
              return;
            }
            setState(() {
              _bannerAd = ad as BannerAd;
              _isAdLoaded = true;
            });
          },
          onAdFailedToLoad: (Ad ad, LoadAdError error) {
            print('BannerAd failed to load: $error');
            ad.dispose();
            // Optionally show a placeholder container instead
          },
        ),
      );

      _bannerAd!.load();
    });
  }

  @override
  void dispose() {
    _bannerAd?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isAdLoaded && _bannerAd != null) {
      return Container(
        alignment: Alignment.center,
        width: _bannerAd!.size.width.toDouble(),
        height: _bannerAd!.size.height.toDouble(),
        child: AdWidget(ad: _bannerAd!),
      );
    }
    // Return a small placeholder or SizedBox when the ad is not loaded
    return const SizedBox(
      height: 50, // Must match the standard banner height
      child: Center(child: Text('Ad Loading/Placeholder')),
    );
  }
}

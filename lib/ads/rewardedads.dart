import 'dart:io' show Platform; // Import dart:io to check the platform

import 'package:google_mobile_ads/google_mobile_ads.dart';

class RewardedAdManager {
  RewardedAd? _rewardedAd;
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

  void loadRewardedAd() {
    RewardedAd.load(
      adUnitId: _adUnitId,
      request: AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (RewardedAd ad) {
          _rewardedAd = ad;
          _isAdLoaded = true;
          _setupAdListeners();
        },
        onAdFailedToLoad: (LoadAdError error) {
          print('Rewarded ad failed to load: $error');
        },
      ),
    );
  }

  void _setupAdListeners() {
    _rewardedAd?.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (RewardedAd ad) {
        print('Ad dismissed full screen content.');
        ad.dispose();
        loadRewardedAd();
      },
      onAdFailedToShowFullScreenContent: (RewardedAd ad, AdError error) {
        print('Ad failed to show full screen content: $error');
        ad.dispose();
        loadRewardedAd();
      },
    );
  }

  void showRewardedAd({Function(RewardItem)? onReward}) {
    if (_isAdLoaded) {
      _rewardedAd?.show(
        onUserEarnedReward: (ad, reward) {
          onReward?.call(reward);
        },
      );
      _isAdLoaded = false;
    }
  }

  void dispose() {
    _rewardedAd?.dispose();
  }
}

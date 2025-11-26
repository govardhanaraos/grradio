import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

typedef RewardedCallback = void Function(RewardItem reward);

/// A static helper class to manage the Interstitial Ad lifecycle.
class AdHelper {
  static InterstitialAd? _interstitialAd;
  static bool _isAdLoading = false;

  static RewardedAd? _rewardedAd;
  static bool _isRewardedAdLoading = false;

  static String get _interstitialAdUnitId {
    // ... platform logic here ...
    return Platform.isAndroid
        ? 'ca-app-pub-3940256099942544/1033173712'
        : 'ca-app-pub-3940256099942544/4411468910';
  }

  // --- NEW: Rewarded Ad Unit ID Getter ---
  static String get _rewardedAdUnitId {
    if (Platform.isAndroid) {
      // Android Test Rewarded ID
      return 'ca-app-pub-3940256099942544/5224354917';
    } else if (Platform.isIOS) {
      // iOS Test Rewarded ID
      return 'ca-app-pub-3940256099942544/1712485313';
    }
    return '';
  }

  /// Loads a new Interstitial Ad.
  static void loadInterstitialAd() {
    if (_isAdLoading ||
        _interstitialAd != null ||
        _interstitialAdUnitId.isEmpty) {
      return;
    }

    _isAdLoading = true;

    InterstitialAd.load(
      adUnitId: _interstitialAdUnitId,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (InterstitialAd ad) {
          print('InterstitialAd loaded successfully.');
          _interstitialAd = ad;
          _isAdLoading = false;
        },
        onAdFailedToLoad: (LoadAdError error) {
          print('InterstitialAd failed to load: $error');
          _interstitialAd = null;
          _isAdLoading = false;
        },
      ),
    );
  }

  // --- NEW: loadRewardedAd() ---
  static void loadRewardedAd() {
    if (_isRewardedAdLoading ||
        _rewardedAd != null ||
        _rewardedAdUnitId.isEmpty) {
      return;
    }

    _isRewardedAdLoading = true;

    RewardedAd.load(
      adUnitId: _rewardedAdUnitId,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (RewardedAd ad) {
          print('RewardedAd loaded successfully.');
          _rewardedAd = ad;
          _isRewardedAdLoading = false;
        },
        onAdFailedToLoad: (LoadAdError error) {
          print('RewardedAd failed to load: $error');
          _rewardedAd = null;
          _isRewardedAdLoading = false;
        },
      ),
    );
  }

  // --- NEW: showRewardedAd() ---
  static Future<void> showRewardedAd({
    required RewardedCallback onUserEarnedReward,
    required VoidCallback onAdFailed,
  }) async {
    if (_rewardedAd == null) {
      print(
        'Warning: Rewarded ad not ready. Executing failure callback immediately.',
      );
      onAdFailed();
      loadRewardedAd();
      return;
    }

    _rewardedAd!.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (RewardedAd ad) {
        print('Rewarded ad dismissed. Preparing new ad.');
        ad.dispose();
        _rewardedAd = null;
        loadRewardedAd(); // Load a new ad for next time
      },
      onAdFailedToShowFullScreenContent: (RewardedAd ad, AdError error) {
        print(
          'Rewarded ad failed to show: $error. Executing failure callback.',
        );
        ad.dispose();
        _rewardedAd = null;
        loadRewardedAd();
        onAdFailed(); // Only execute the failure callback here
      },
    );

    // Show the ad and handle the reward logic
    await _rewardedAd!.show(
      onUserEarnedReward: (AdWithoutView ad, RewardItem rewardItem) {
        print('User earned reward: ${rewardItem.amount} ${rewardItem.type}');
        onUserEarnedReward(rewardItem); // Execute the custom reward callback
      },
    );
  }

  /// Shows the loaded Interstitial Ad, or executes the callback immediately if the ad is not ready.
  /// A new ad is automatically loaded after the current one is dismissed.
  static void showInterstitialAd({required VoidCallback onAdClosed}) {
    // Check if the ad is loaded
    if (_interstitialAd != null) {
      // Set the full screen content callback
      _interstitialAd!.fullScreenContentCallback = FullScreenContentCallback(
        onAdDismissedFullScreenContent: (InterstitialAd ad) {
          // 1. Dispose of the ad
          ad.dispose();
          _interstitialAd = null;

          // 2. Call the required callback
          onAdClosed(); // 💡 CRITICAL: This now executes the playNext() logic

          // 3. Start loading the next ad immediately
          loadInterstitialAd();
        },
        onAdFailedToShowFullScreenContent: (InterstitialAd ad, AdError error) {
          // If the ad fails to show, we must still trigger the next song!
          print('Interstitial Ad failed to show: $error');
          ad.dispose();
          _interstitialAd = null;

          onAdClosed(); // 💡 Call the callback even on failure
          loadInterstitialAd();
        },
      );

      // Show the ad
      _interstitialAd!.show();
    } else {
      // If ad is not ready, immediately call the callback to continue playback
      onAdClosed();
      loadInterstitialAd();
    }
  }

  /// Disposes of the ad object. Call this, for example, in your main application's dispose method.
  static void disposeAd() {
    _interstitialAd?.dispose();
    _interstitialAd = null;
  }
}

// Copyright 2016 Google Inc.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

#import "GADMAdapterUnity.h"

#import "GADMAdapterUnityConstants.h"
#import "GADMAdapterUnitySingleton.h"
#import "GADMediationAdapterUnity.h"
#import "GADUnityError.h"
#import "GADMAdapterUnityBannerAd.h"

@interface GADMAdapterUnity () {
  /// Connector from Google Mobile Ads SDK to receive ad configurations.
  __weak id<GADMAdNetworkConnector> _networkConnector;

  /// Game ID of Unity Ads network.
  NSString *_gameID;

  /// Placement ID of Unity Ads network.
  NSString *_placementID;

  /// Unity Ads Banner wrapper
  GADMAdapterUnityBannerAd *_bannerAd;
  
  NSString *_uuid;

  UADSMetaData *_metaData;
}

@end

@implementation GADMAdapterUnity

+ (nonnull Class<GADMediationAdapter>)mainAdapterClass {
  return [GADMediationAdapterUnity class];
}

+ (NSString *)adapterVersion {
  return kGADMAdapterUnityVersion;
}

+ (Class<GADAdNetworkExtras>)networkExtrasClass {
  return Nil;
}

- (void)stopBeingDelegate {
  if (_bannerAd != nil) {
    [_bannerAd stopBeingDelegate];
  }
  [UnityAds removeDelegate:self];
}

#pragma mark Interstitial Methods

- (instancetype)initWithGADMAdNetworkConnector:(id<GADMAdNetworkConnector>)connector {
  if (!connector) {
    return nil;
  }

  self = [super init];
  if (self) {
    _networkConnector = connector;
    _uuid = [[NSUUID UUID] UUIDString];
    
    _metaData = [[UADSMetaData alloc] init];
    
    [_metaData setCategory:@"mediation_adapter"];
    [_metaData set:_uuid value:@"create-adapter"];
    [_metaData commit];
  }
  return self;
}

- (void)getInterstitial {
  id<GADMAdNetworkConnector> strongConnector = _networkConnector;
  _gameID = [[[strongConnector credentials] objectForKey:kGADMAdapterUnityGameID] copy];
  _placementID = [[[strongConnector credentials] objectForKey:kGADMAdapterUnityPlacementID] copy];
  if (!_gameID || !_placementID) {
    NSError *error = GADUnityErrorWithDescription(@"Game ID and Placement ID cannot be nil.");
    [strongConnector adapter:self didFailAd:error];
    return;
  }

  UnitySingletonCompletion completeBlock = ^(UnityAdsError *error, NSString *message) {
    if(error) {
      if (strongConnector) {
        NSError *errorWithDescription = GADUnityErrorWithDescription(message);
        [strongConnector adapter:self didFailAd:errorWithDescription];
      }
      return;
    }
    [UnityAds addDelegate:self];
    [UnityAds load:[self getPlacementID]];
  };
    
  [[GADMAdapterUnitySingleton sharedInstance] initializeWithGameID:_gameID
                                                       completeBlock:completeBlock];
    
  [_metaData setCategory:@"mediation_adapter"];
  [_metaData set:_uuid value:@"load-interstitial"];
  [_metaData set:_uuid value:_placementID];
  [_metaData commit];
}

- (void)presentInterstitialFromRootViewController:(UIViewController *)rootViewController {
    [UnityAds show:rootViewController placementId:_placementID];
    
    [_metaData setCategory:@"mediation_adapter"];
    [_metaData set:_uuid value:@"show-interstitial"];
    [_metaData set:_uuid value:_placementID];
    [_metaData commit];
}

#pragma mark Banner Methods

- (void)getBannerWithSize:(GADAdSize)adSize {
  id<GADMAdNetworkConnector> strongConnector = _networkConnector;
  _gameID = [strongConnector.credentials[kGADMAdapterUnityGameID] copy];
  _placementID = [strongConnector.credentials[kGADMAdapterUnityPlacementID] copy];
  if (!_gameID || !_placementID) {
    NSError *error = GADUnityErrorWithDescription(@"Game ID and Placement ID cannot be nil.");
    [strongConnector adapter:self didFailAd:error];
    return;
  }

  _bannerAd = [[GADMAdapterUnityBannerAd alloc] initWithGADMAdNetworkConnector:strongConnector
                                                                       adapter:self];
  [_bannerAd loadBannerWithSize:adSize];
}

#pragma mark GADMAdapterUnityDataProvider Methods

- (NSString *)getGameID {
  return _gameID;
}

- (NSString *)getPlacementID {
  return _placementID;
}

#pragma mark - Unity Delegate Methods

- (void)unityAdsPlacementStateChanged:(NSString *)placementID
                             oldState:(UnityAdsPlacementState)oldState
                             newState:(UnityAdsPlacementState)newState {
  id<GADMAdNetworkConnector> strongNetworkConnector = _networkConnector;
  if (strongNetworkConnector && [placementID isEqualToString:_placementID]) {
    if (newState == kUnityAdsPlacementStateNoFill){
      NSError *errorWithDescription = GADUnityErrorWithDescription(@"NO_FILL");
      [strongNetworkConnector adapter:self didFailAd:errorWithDescription];
    } else if (newState == kUnityAdsPlacementStateDisabled) {
      NSError *errorWithDescription = GADUnityErrorWithDescription(@"PlACEMENT_DISABLED");
      [strongNetworkConnector adapter:self didFailAd:errorWithDescription];
    } else if (newState == kUnityAdsPlacementStateNotAvailable) {
      NSError *errorWithDescription = GADUnityErrorWithDescription(@"PlACEMENT_NOTAVAILABLE");
      [strongNetworkConnector adapter:self didFailAd:errorWithDescription];
    }
  }
}

- (void)unityAdsDidFinish:(NSString *)placementID withFinishState:(UnityAdsFinishState)state {
  id<GADMAdNetworkConnector> strongNetworkConnector = _networkConnector;
  if (strongNetworkConnector && [placementID isEqualToString:_placementID]) {
    if (state == kUnityAdsFinishStateCompleted) {
      [strongNetworkConnector adapterDidDismissInterstitial:self];
    } else if (state == kUnityAdsFinishStateError) {
      [strongNetworkConnector adapterWillPresentInterstitial:self];
      [strongNetworkConnector adapterDidDismissInterstitial:self];
    } else if (state == kUnityAdsFinishStateSkipped) {
      [strongNetworkConnector adapterDidDismissInterstitial:self];
    }
    [UnityAds removeDelegate:self];
  }
}

- (void)unityAdsReady:(NSString *)placementID {
  id<GADMAdNetworkConnector> strongNetworkConnector = _networkConnector;
  if (strongNetworkConnector && [placementID isEqualToString:_placementID]) {
    [strongNetworkConnector adapterDidReceiveInterstitial:self];
  }
}

- (void)unityAdsDidClick:(NSString *)placementID {
  id<GADMAdNetworkConnector> strongNetworkConnector = _networkConnector;
  // The Unity Ads SDK doesn't provide an event for leaving the application, so the adapter assumes
  // that a click event indicates the user is leaving the application for a browser or deeplink, and
  // notifies the Google Mobile Ads SDK accordingly.
  if (strongNetworkConnector && [placementID isEqualToString:_placementID]) {
    [strongNetworkConnector adapterDidGetAdClick:self];
    [strongNetworkConnector adapterWillLeaveApplication:self];
  }
}

- (void)unityAdsDidError:(UnityAdsError)error withMessage:(NSString *)message {
  //do nothing.
}

- (void)unityAdsDidStart:(nonnull NSString *)placementID {
  id<GADMAdNetworkConnector> strongNetworkConnector = _networkConnector;
  if (strongNetworkConnector && [placementID isEqualToString:_placementID]) {
    [strongNetworkConnector adapterWillPresentInterstitial:self];
  }
}

@end

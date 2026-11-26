import 'package:flutter/foundation.dart';

const xyCarAppId = String.fromEnvironment(
  'APP_SERVICE_ID',
  defaultValue: 'xy_car_app',
);
const xyCarReleaseId = 'xy_car_app';

const xyCarServiceOrigin = String.fromEnvironment(
  'APP_SERVICE_ORIGIN',
  defaultValue: 'https://cznas.pp.ua:18281',
);
const useLiveAccountService = bool.fromEnvironment(
  'XY_CAR_LIVE_ACCOUNT',
  defaultValue: kReleaseMode,
);
const xyCarReleaseOrigin = String.fromEnvironment('XY_CAR_RELEASE_ORIGIN');

const xyCarVehicleOrigin = String.fromEnvironment(
  'XY_CAR_VEHICLE_ORIGIN',
  defaultValue: 'https://cznas.pp.ua:8090',
);

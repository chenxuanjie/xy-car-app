import 'dart:ffi';

String get androidArchitecture => switch (Abi.current()) {
  Abi.androidArm => 'arm',
  Abi.androidX64 => 'x64',
  Abi.androidIA32 => 'x86',
  _ => 'arm64',
};

/// Utils to open a [DynamicLibrary] on platforms that aren't supported by
/// default.
@Deprecated('Replaced with native assets feature')
library open;

import 'dart:ffi';

export 'src/ffi/load_library.dart';

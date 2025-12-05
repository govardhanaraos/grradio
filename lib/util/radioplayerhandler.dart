import 'radio_handler_mobile.dart'
    if (dart.library.html) 'radio_handler_web.dart';

// ✅ Export the concrete class directly
export 'radio_handler_base.dart';

// This way, RadioPlayerHandler resolves to the right concrete class
typedef RadioPlayerHandler = RadioHandlerImpl;

class Endpoints {
  static const String login = '/auth/login';
  static const String refresh = '/auth/refresh';
  static const String logout = '/auth/logout';
  static const String agentProfile = '/agent/profile';
  static const String agentTrips = '/agent/trips';
  static const String generateToken = '/agent/generate-token';
  static const String walletPayment = '/agent/wallet-payment';
  static String agentCheckin(String tripId, String bookingId) => '/agent/trips/$tripId/checkin/$bookingId';
  static String agentBookingLookup(String ref) => '/agent/bookings/$ref';
  static String agentBookingScan(String ref) => '/agent/bookings/scan/$ref';
  static String agentBookingPay(String ref) => '/agent/bookings/$ref/pay';
}

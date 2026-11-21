class AppRoutes {
  // Prevent instantiation
  AppRoutes._();

  // ========================================================
  // CORE & ONBOARDING
  // ========================================================
  static const String onboarding = '/onboarding';
  static const String home = '/home';

  // ========================================================
  // JOBS (CUSTOMER FLOW)
  // ========================================================
  /// Base route for the Job Dashboard (Jobs tab)

  static const String jobs = "/jobs";

  /// Filtered & paginated job list screen (accepts ?status=PENDING|...)
  static const String jobList = '/jobs/list';

  /// Base path for single job details (append '/$jobId')
  static const String jobDetail = '/jobs/detail';
  static const String jobDetailPattern = '/jobs/detail/:jobId';

  /// Job creation screen (supports optional ?categoryId=<uuid>)
  static const String createJob = '/create-job';
  static const String jobCreate = createJob;

  /// Base path for editing a PENDING job (append '/$jobId')
  static const String editJob = '/edit-job';
  static const String jobEdit = editJob;
  static const String jobEditPattern = '/edit-job/:jobId';

  // ========================================================
  // CHATS
  // ========================================================
  static const String chatList = '/chats'; // Base route for the inbox tab
  static const String chatDetail = '/chat'; // Base route for the detail screen
  static const String chatDetailPattern = '/chat/:sessionId/:partnerId';

  // ========================================================
  // SUPPORT, NOTIFICATIONS & PROFILE
  // ========================================================
  static const String support = '/support';
  static const String notifications = '/notifications';
  static const String profileDummy = '/profile';
  static const String profileEdit = '/profile/edit';

  static const String paymentMethods = '/profile/payment-methods';
  static const String customerTransactions = '/profile/transactions';

  // ========================================================
  // TYPE-SAFE NAVIGATION HELPERS
  // ========================================================
  static String jobListByStatus(String status) =>
      '$jobList?status=${Uri.encodeQueryComponent(status)}';

  static String jobDetailById(String jobId) => '$jobDetail/$jobId';

  static String jobEditById(String jobId) => '$jobEdit/$jobId';

  static String jobCreateWithCategory(String? categoryId) =>
      (categoryId != null && categoryId.isNotEmpty)
      ? '$jobCreate?categoryId=${Uri.encodeQueryComponent(categoryId)}'
      : jobCreate;

  static String chatDetailByIds(String sessionId, String partnerId) =>
      '$chatDetail/$sessionId/$partnerId';
}

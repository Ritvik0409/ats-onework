// The employee feed and the management feed are the same owner-scoped
// endpoint and the same presentation, so this file only re-exports the
// shared hub. It used to duplicate the whole screen with dark-only
// colours, which broke in the light theme.
export '../management/notifications_hub.dart' show EmployeeNotificationsScreen;

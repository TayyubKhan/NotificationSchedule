Scheduled Notifications App - README
Overview
This Flutter project demonstrates how to implement a background notification scheduling system. It enables users to schedule notifications for future dates and times. Notifications are managed in the background using WorkManager and displayed using flutter_local_notifications. Data persistence is handled with Hive.

Features
Schedule Notifications: Users can schedule notifications with custom titles, bodies, and timings.
Persistent Storage: Notifications are stored in a Hive database for persistence.
Background Task Execution: Notifications are scheduled and executed even when the app is in the background.
Notification Management: Users can view and delete scheduled notifications.
Test Notification: Quick testing feature to schedule a notification 15 seconds in the future.
Tech Stack
Flutter: Cross-platform app framework.
flutter_local_notifications: For local notifications.
Hive: Lightweight and fast local database.
WorkManager: To handle background tasks.
timezone: For accurate scheduling.

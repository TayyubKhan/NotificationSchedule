import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:uuid/uuid.dart';
import 'package:workmanager/workmanager.dart';

@HiveType(typeId: 0)
class ScheduledNotification extends HiveObject {
  @HiveField(0)
  final String id;

  @HiveField(1)
  final String title;

  @HiveField(2)
  final String body;

  @HiveField(3)
  final DateTime scheduledDate;

  ScheduledNotification({
    required this.id,
    required this.title,
    required this.body,
    required this.scheduledDate,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'body': body,
      'scheduledDate': scheduledDate.toIso8601String(),
    };
  }

  static ScheduledNotification fromJson(Map<String, dynamic> json) {
    return ScheduledNotification(
      id: json['id'],
      title: json['title'],
      body: json['body'],
      scheduledDate: DateTime.parse(json['scheduledDate']),
    );
  }
}

// This needs to be top-level function
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((taskName, inputData) async {
    try {
      // Initialize notifications
      final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

      const AndroidInitializationSettings initializationSettingsAndroid =
      AndroidInitializationSettings('@mipmap/ic_launcher');

      const InitializationSettings initializationSettings =
      InitializationSettings(android: initializationSettingsAndroid);

      await flutterLocalNotificationsPlugin.initialize(initializationSettings);

      // Create the notification channel
      final AndroidFlutterLocalNotificationsPlugin? androidImplementation =
      flutterLocalNotificationsPlugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();

      await androidImplementation?.createNotificationChannel(
        const AndroidNotificationChannel(
          'scheduled_notifications',
          'Scheduled Notifications',
          description: 'Notifications scheduled by user',
          importance: Importance.max,
          playSound: true,
          enableVibration: true,
        ),
      );

      // Show notification
      if (inputData != null) {
        await flutterLocalNotificationsPlugin.show(
          inputData['id'].hashCode,
          inputData['title'],
          inputData['body'],
          const NotificationDetails(
            android: AndroidNotificationDetails(
              'scheduled_notifications',
              'Scheduled Notifications',
              channelDescription: 'Notifications scheduled by user',
              importance: Importance.max,
              priority: Priority.high,
              playSound: true,
              enableVibration: true,
              fullScreenIntent: true,
            ),
          ),
        );
      }

      return true;
    } catch (e) {
      print('Error in background task: $e');
      return false;
    }
  });
}

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  Future<void> initialize() async {
    // Initialize WorkManager
    await Workmanager().initialize(
      callbackDispatcher,
      isInDebugMode: true,
    );

    // Request notification permissions
    final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

    final AndroidFlutterLocalNotificationsPlugin? androidImplementation =
    flutterLocalNotificationsPlugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();

    await androidImplementation?.requestNotificationsPermission();
    await androidImplementation?.requestExactAlarmsPermission();
    await androidImplementation?.requestFullScreenIntentPermission();

    // Create notification channel
    await androidImplementation?.createNotificationChannel(
      const AndroidNotificationChannel(
        'scheduled_notifications',
        'Scheduled Notifications',
        description: 'Notifications scheduled by user',
        importance: Importance.max,
        playSound: true,
        enableVibration: true,
      ),
    );
  }

  Future<void> scheduleNotification(ScheduledNotification notification) async {
    try {
      // Calculate delay
      final delay = notification.scheduledDate.difference(DateTime.now());
      if (delay.isNegative) {
        throw Exception('Cannot schedule notification in the past');
      }

      // Schedule work manager task
      await Workmanager().registerOneOffTask(
        notification.id, // Unique name
        'showNotification', // Task name
        initialDelay: delay,
        inputData: notification.toJson(),
        existingWorkPolicy: ExistingWorkPolicy.replace,
      );

      debugPrint('Scheduled notification with WorkManager: ${notification.id}');
    } catch (e) {
      debugPrint('Error scheduling notification: $e');
      rethrow;
    }
  }

  Future<void> cancelNotification(String id) async {
    await Workmanager().cancelByUniqueName(id);
  }

  Future<void> cancelAllNotifications() async {
    await Workmanager().cancelAll();
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Hive
  await Hive.initFlutter();
  Hive.registerAdapter(ScheduledNotificationAdapter());
  await Hive.openBox<ScheduledNotification>('notifications');

  // Initialize timezone data
  tz.initializeTimeZones();

  // Initialize notifications service
  await NotificationService().initialize();

  runApp(MaterialApp(
    title: 'Scheduled Notifications',
    theme: ThemeData(
      primarySwatch: Colors.blue,
      useMaterial3: true,
    ),
    home: const NotificationHomePage(),
  ));
}

class NotificationHomePage extends StatefulWidget {
  const NotificationHomePage({super.key});

  @override
  State<NotificationHomePage> createState() => _NotificationHomePageState();
}

class _NotificationHomePageState extends State<NotificationHomePage> {
  final _titleController = TextEditingController();
  final _bodyController = TextEditingController();
  DateTime? _selectedDateTime;
  bool _isScheduling = false;

  Future<void> _scheduleTestNotification() async {
    try {
      final notification = ScheduledNotification(
        id: const Uuid().v4(),
        title: 'Test Notification',
        body: 'This should appear in 15 seconds!',
        scheduledDate: DateTime.now().add(const Duration(seconds: 15)),
      );

      // Save to Hive
      final box = Hive.box<ScheduledNotification>('notifications');
      await box.add(notification);

      // Schedule notification
      await NotificationService().scheduleNotification(notification);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Test notification scheduled for 15 seconds from now'),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
  }

  Future<void> _selectDateTime() async {
    final DateTime? date = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );

    if (date == null) return;

    if (!mounted) return;

    final TimeOfDay? time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
    );

    if (time == null) return;

    setState(() {
      _selectedDateTime = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      );
    });
  }

  Future<void> _scheduleNotification() async {
    if (_selectedDateTime == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a date and time')),
      );
      return;
    }

    if (_titleController.text.isEmpty || _bodyController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill in all fields')),
      );
      return;
    }

    setState(() => _isScheduling = true);

    try {
      final notification = ScheduledNotification(
        id: const Uuid().v4(),
        title: _titleController.text,
        body: _bodyController.text,
        scheduledDate: _selectedDateTime!,
      );

      // Save to Hive
      final box = Hive.box<ScheduledNotification>('notifications');
      await box.add(notification);

      // Schedule notification
      await NotificationService().scheduleNotification(notification);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Notification scheduled successfully')),
      );

      // Clear form
      _titleController.clear();
      _bodyController.clear();
      setState(() => _selectedDateTime = null);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error scheduling notification: $e')),
      );
    } finally {
      setState(() => _isScheduling = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Background Notifications'),
        actions: [
          IconButton(
            icon: const Icon(Icons.notification_add),
            onPressed: _scheduleTestNotification,
            tooltip: 'Schedule test notification (15 seconds)',
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: _titleController,
                    decoration: const InputDecoration(
                      labelText: 'Notification Title',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _bodyController,
                    decoration: const InputDecoration(
                      labelText: 'Notification Body',
                      border: OutlineInputBorder(),
                    ),
                    maxLines: 3,
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: _selectDateTime,
                    icon: const Icon(Icons.calendar_today),
                    label: Text(_selectedDateTime == null
                        ? 'Select Date & Time'
                        : 'Selected: ${_selectedDateTime!.toString()}'),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: _isScheduling ? null : _scheduleNotification,
                    child: _isScheduling
                        ? const CircularProgressIndicator()
                        : const Text('Schedule Notification'),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: ValueListenableBuilder(
              valueListenable:
              Hive.box<ScheduledNotification>('notifications').listenable(),
              builder: (context, Box<ScheduledNotification> box, _) {
                if (box.isEmpty) {
                  return const Center(
                    child: Text('No scheduled notifications'),
                  );
                }

                return ListView.builder(
                  itemCount: box.length,
                  itemBuilder: (context, index) {
                    final notification = box.getAt(index);
                    return Dismissible(
                      key: Key(notification!.id),
                      onDismissed: (direction) async {
                        await NotificationService()
                            .cancelNotification(notification.id);
                        await box.deleteAt(index);
                      },
                      background: Container(
                        color: Colors.red,
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.only(right: 16),
                        child: const Icon(Icons.delete, color: Colors.white),
                      ),
                      child: ListTile(
                        title: Text(notification.title),
                        subtitle: Text(
                          '${notification.body}\nScheduled for: ${notification.scheduledDate}',
                        ),
                        trailing: const Icon(Icons.notifications),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _titleController.dispose();
    _bodyController.dispose();
    super.dispose();
  }
}

// Hive type adapter
class ScheduledNotificationAdapter extends TypeAdapter<ScheduledNotification> {
  @override
  final int typeId = 0;

  @override
  ScheduledNotification read(BinaryReader reader) {
    return ScheduledNotification(
      id: reader.read(),
      title: reader.read(),
      body: reader.read(),
      scheduledDate: reader.read(),
    );
  }

  @override
  void write(BinaryWriter writer, ScheduledNotification obj) {
    writer.write(obj.id);
    writer.write(obj.title);
    writer.write(obj.body);
    writer.write(obj.scheduledDate);
  }
}
import 'package:pigeon/pigeon.dart';

@ConfigurePigeon(
  PigeonOptions(
    dartOut: 'lib/platform/account_manager_api.g.dart',
    // swiftOut: 'ios/Runner/Connectivity/Connectivity.g.swift',
    // swiftOptions: SwiftOptions(includeErrorClass: false),
    kotlinOut: 'android/app/src/main/kotlin/com/seagate/curator/stxphotos/android/accountmanager/AccountManager.g.kt',
    kotlinOptions: KotlinOptions(package: 'com.seagate.curator.stxphotos.android.accountmanager'),
    dartOptions: DartOptions(),
    dartPackageName: 'personal_cloud_photos',
  ),
)

class Account {
  String name;
  String type;
  
  Account({
    required this.name,
    required this.type,
  });
}

@HostApi()
abstract class AccountManagerApi {
  @async
  Account addAccount(Account account, String password);
  
  @async
  List<Account> getAccounts();
  
  @async
  bool removeAccount(Account account);
  
  @async
  bool hasAccount(String accountName, String accountType);
  
  @async
  bool setUserData(Account account, Map<String, String?> userData);
  
  @async
  Map<String, String?> getUserData(Account account, List<String> keys);
  
  @async
  String? getPassword(Account account);
  
  @async
  bool setPassword(Account account, String? password);
  
  @async
  bool removeUserData(Account account, List<String> keys);
}
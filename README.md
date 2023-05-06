<!--
This README describes the package. If you publish this package to pub.dev,
this README's contents appear on the landing page for your package.

For information about how to write a good package README, see the guide for
[writing package pages](https://dart.dev/guides/libraries/writing-package-pages).

For general information about developing packages, see the Dart guide for
[creating packages](https://dart.dev/guides/libraries/create-library-packages)
and the Flutter guide for
[developing packages and plugins](https://flutter.dev/developing-packages).
-->

To prevent create a lot of Isolate dart, Just create Isolate as worker, number of workers max by cpu count, when it free use it for invoke action

## Features

- Just wrap Isolate with simple way to use eg: 

```dart
    Future<void> doOnce(
    {required dynamic dataToDo,
    required Future<dynamic> Function(dynamic) doInBackground,
    Future<void> Function(dynamic)? onResult}) async {}
```

## Getting started

In pubspec.yaml

```dart
dev_dependencies:
  dart_isolate_pool:
    git: https://github.com/badpaybad/dart_isolate_pool.git
    ref: main

```

```dart
    import 'package:dart_isolate_pool/shelf.dart';
```
## Usage

TODO: Include short and useful examples for package users. Add longer examples
to `/example` folder.

```dart
    IsolatePoolServe.instance.doOnce(
    dataToDo: [1,"a",[3.4, 0.5]],
    doInBackground: (dataIn) async {
    print("doIt first time: $dataIn");
    int int1 = dataIn[0];
    String str2 = dataIn[1];
    List<double> lst3 = dataIn[2];
    lst3.add(int1.toDouble());
    await Future.delayed(const Duration(seconds: 1)); //fake long process
    return ["done", lst3]; //should be do sth return as dataOut
    },
    onResult: (dataOut) async {
    var msg = dataOut[0];
    var lstres = dataOut[1];
    print("onResult: $dataOut");
    });
```
```dart

  var sendMany = await IsolateSingleServe().withBackgroundFunction((p0) async {
    print("Send many $p0");
    await Future.delayed(const Duration(seconds: 1));
    return p0;
  }).withOnResultFunction((p0) async {
    //if mounted setState
    print("On result $p0");
  }).initToSendManyDatas();

  for (var i = 0; i < 100; i++) {
    sendMany.sendData("${DateTime.now()}");
  }


```

## Additional information

Donate me: https://www.paypal.com/paypalme/dunp211284

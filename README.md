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


var sendMany =
    await IsolateSingleServe().withBackgroundFunction((p0, contextDi) async {
print("Send many args to do in Bg: $p0");
await Future.delayed(const Duration(seconds: 1));

//use object in DI collection , no need to create new one
var testObjDI = contextDi["TestObjectResult"];

print("DI-TestObjectResult $testObjDI");

return "$p0 ---- ${DateTime.now()}";
}).withOnResultFunction((p0) async {
//if mounted setState
print("On result $p0");
}).initSendManyTimes(diBuilder: () async {
var mapDI = <String, TestObjectResult>{};
mapDI["TestObjectResult"] = TestObjectResult();
return mapDI;
});

for (var i = 0; i < 5; i++) {
var dataToDoInBg = "sendMany.sendData ${DateTime.now()}";
print(dataToDoInBg);
sendMany.sendData(dataToDoInBg);
}

sendMany.closeSendManyTimes();

```

# use in flutter eg do smth related to image

````dart

import 'package:image/image.dart' as DartImage;

import 'package:http/http.dart' as http;
...


var imgAiLogo = (await http.get(Uri.parse(
"https://avatars.githubusercontent.com/u/6204507?v=4")));

DartImage.Image img = DartImage.decodeImage( imgAiLogo.bodyBytes)!;

IsolatePoolServe.instance.doOnce(
dataToDo: imgAiLogo.bodyBytes,
doInBackground: (dataIn) async {
var x = DartImage.decodeJpg(Uint8List.fromList(List<int>.from(dataIn)));

var croped = DartImage.copyCrop(x!, x: 10, y: 10, width: 20, height: 20);
var cropedJpg = DartImage.encodeJpg(croped);
return Uint8List.fromList(cropedJpg);

}, onResult: (img)async{
_visionImage = img
if (mounted) setState(() {});
});

...
Image.memory(
_visionImage!,
gaplessPlayback: true,
fit: orient == Orientation.portrait
? BoxFit.fitWidth
    : BoxFit.fitHeight,
)
  
````

## Additional information

Buy me a coffe: https://www.paypal.com/paypalme/dunp211284

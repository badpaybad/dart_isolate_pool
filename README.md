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

IsolateSingleServe as worker

IsolatePoolServe as manager, who will know which worker is free to do job 

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

# pub sub Isolate

Provide do some thing inside Isolate as background, and work similar pub sub. 
Can do as singleton, or init once at void main. 
So that you can use only one Isolate for all application :) 

````dart


  print("--------------------- do publish sub isolate ");
// can do as singleton, or init once at void main. 
  var pubsub = IsolatePubSubServe();

  //should do: declare in your initState
  
  pubsub.AddBgHandleAndOnResult("test", (args, dicontext) async {
    //args come from pubsub.Publish
    //this will run inside Isolate
    var i = args[0];
    var time = args[1];

    return ["$i -> test -> $time"]; // will be result
  }, (result) async {
    //result when bgFunc done in Isolate,
    //this will run in UI thread
    print("result $result");
  });
  //should do: declare in your initState
  pubsub.AddBgHandleAndOnResult("test1", (args, dicontext) async {
    //args come from pubsub.Publish
    //this will run inside Isolate
    var i = args[0];
    var time = args[1];

    var diTest = dicontext["TestObjectResult"];

    return [
      "$i -> TEST 1 -> $time",
      diTest
    ]; // will be result, just topic test1 got di obj in result, cause we add diBuilder
  }, (result) async {
    //result when bgFunc done in Isolate,
    //this will run in UI thread
    print("result $result");
  });
  //should do: declare in your initState
  Map<String, Future<Map<String, dynamic>> Function()> diBuilder =
      <String, Future<Map<String, dynamic>> Function()>{};

  diBuilder["test1"] = () async {
    var mapDI = <String, TestObjectResult>{};
    mapDI["TestObjectResult"] = TestObjectResult();
    return mapDI;
  };
  //should do: declare in your initState
  pubsub.InitPublish(diBuilder: diBuilder);

  for (var i in [1, 2, 3]) {
    //call this to issues data to bg do, eg button click
    await pubsub.Publish("test", [i, DateTime.now()]);
    await pubsub.Publish("test1", [i, DateTime.now()]);
  }

  await Future.delayed(const Duration(seconds: 2));

  print("------- add new DoInBackground, new DiBuilder AfterInit spawn");
  //should do: declare in your initState
  pubsub.AddBackgroundFunction("test2", (args, diCollection) async {
    var diTest2 = diCollection["Test2Di"];

    return [args, diTest2];
  });
  //should do: declare in your initState
  pubsub.AddDiBuilderFunction("test2", () async {
    var mapDI = <String, TestObjectResult>{};
    mapDI["Test2Di"] = TestObjectResult();
    return mapDI;
  });
  //should do: declare in your initState
  pubsub.AddOnResultFunction("test2", (p0) async {
    print("Test2 resutl include DI $p0");
  });

  //call this to issues data to bg do, eg button click
  await pubsub.Publish("test2", ["a", 1, "b"]);

````

# use in flutter eg do smth related to image

````dart

import 'package:image/image.dart' as DartImage;

import 'package:http/http.dart' as http;
...


var imgAiLogo = (await http.get(Uri.parse(
"https://avatars.githubusercontent.com/u/6204507?v=4")));

//DartImage.Image img = DartImage.decodeImage( imgAiLogo.bodyBytes)!;

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

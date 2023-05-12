//import 'package:flutter_test/flutter_test.dart';

import 'dart:typed_data';

import 'package:dart_isolate_pool/shelf.dart';

Future<void> main() async {
  IsolatePoolServe.instance.doOnce(
      dataToDo: [
        1,
        "a",
        [3.4, 0.5]
      ],
      doInBackground: (dataIn) async {
        print("parse args for do in background: $dataIn");
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
        print("onResult doIt first time: $dataOut");
      });

  for (var i = 0; i < 5; i++) {
    IsolatePoolServe.instance.doOnce(
        dataToDo: i,
        doInBackground: (dataIn) async {
          print(
              "${DateTime.now()} doIt 2nd, it will wait 1st doIt $dataIn and no need handle result, onResult=null");
        });
  }

  IsolatePoolServe.instance.doOnce(
      dataToDo: [
        "dunp",
        Uint8List.fromList([19, 3, 4])
      ],
      doInBackground: (args) async {
        var testobj = TestObjectResult();
        testobj.name = "${testobj.name}/added new/$args/";
        return testobj;
      },
      onResult: (res) async {
        print(res);
      });

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

  print("--------------------- do publish isolate ");

  var pubsub = IsolatePubSubServe();

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

  Map<String, Future<Map<String, dynamic>> Function()> diBuilder =
      <String, Future<Map<String, dynamic>> Function()>{};

  diBuilder["test1"] = () async {
    var mapDI = <String, TestObjectResult>{};
    mapDI["TestObjectResult"] = TestObjectResult();
    return mapDI;
  };

  pubsub.InitPublish(diBuilder: diBuilder);

  for (var i in [1, 2, 3]) {
    await pubsub.Publish("test", [i, DateTime.now()]);
    await pubsub.Publish("test1", [i, DateTime.now()]);
  }

  await Future.delayed(const Duration(seconds: 2));

  print("------- add new DoInBackground, new DiBuilder AfterInit spawn");

  pubsub.AddBackgroundFunction("test2", (args, diCollection) async {
    var diTest2 = diCollection["Test2Di"];

    return [args, diTest2];
  });

  pubsub.AddDiBuilderFunction("test2", () async {
    var mapDI = <String, TestObjectResult>{};
    mapDI["Test2Di"] = TestObjectResult();
    return mapDI;
  });

  pubsub.AddOnResultFunction("test2", (p0) async {
    print("Test2 resutl include DI $p0");
  });

  await pubsub.Publish("test2", ["a", 1, "b"]);

  while (true) {
    await Future.delayed(const Duration(seconds: 5));
    print("elapsed ${DateTime.now()}");
  }
}

class TestObjectResult {
  int age = 123;
  String name = "dunp";

  @override
  String toString() {
    return "name: $name age: $age";
  }
}

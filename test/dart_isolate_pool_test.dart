//import 'package:flutter_test/flutter_test.dart';

import 'dart:math';
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

  print("--------------------- do publish isolate ");

  var pubsub = IsolatePubSubServe.instance;

  await Future.delayed(const Duration(seconds: 2));

  print("------- add new DoInBackground, new DiBuilder AfterInit spawn");

  await pubsub.AddEnvs({"test2_id": "123"});

  await pubsub.AddDiBuilderFunction("test2", (envs) async {
    var mapDI = <String, TestObjectResult>{};
    var xxx = TestObjectResult();
    xxx.name = "Test2Di after spawn init";
    mapDI["Test2Di"] = xxx;

    print("AddDiBuilderFunction do logic with envs: $envs");
    return mapDI;
  });

  await pubsub.AddBackgroundFunction("test2", (args, diCollection, envs) async {
    var diTest2 = diCollection["Test2Di"];
    print("AddBackgroundFunction do logic with envs: $envs");
    await Future.delayed(const Duration(seconds: 3));
    return [args, diTest2];
  });

  await pubsub.AddOnResultFunction("test2", (p0, envs) async {
    print("Test2 resutl include DI: $p0 with envs: $envs");
  });

  await pubsub.AddBackgroundFunction("test3", (args, diCollection, envs) async {

    print("test3 AddBackgroundFunction do logic with envs: $envs");
    return [args];
  });

  await pubsub.AddOnResultFunction("test3", (p0, envs) async {
    print("test3 resutl include DI: $p0 with envs: $envs");
  });

  await pubsub.Publish("test2", ["a", 1, "b"]);
  await pubsub.Publish("test3", ["this is test 3", 1, 0.5]);

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

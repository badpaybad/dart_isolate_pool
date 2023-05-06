//import 'package:flutter_test/flutter_test.dart';

import 'package:dart_isolate_pool/shelf.dart';

Future<void> main() async {
  //var isolateSingle= IsolateSingleServe();
  IsolatePoolServe.instance.doIt(
      dataToDo: [
        1,
        "a",
        [3.4, 0.5]
      ],
      doInBackground: (dataIn) async {
        print("doIt : $dataIn");
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

  for (var i = 0; i < 300; i++) {
    IsolatePoolServe.instance.doIt(
        dataToDo: i,
        doInBackground: (dataIn) async {
          print("ddoIt $dataIn and no need handle result, onResult=null");
        });
  }

  await Future.delayed(const Duration(seconds: 5));
}

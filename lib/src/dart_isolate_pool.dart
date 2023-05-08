library dart_isolate_pool;

import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';


class IsolateSingleServe {
  //static IsolateSingleServe instance = IsolateSingleServe._();

  bool _isDone = false;

  String _topicDoIt = "DoIt";
  static const String _topicPing = "____ping____";
  bool _isDoing = false;

  bool _isSendOnce = true;

  IsolateSingleServe({String topic = "doIt"}) {
    _topicDoIt = "${topic}_${DateTime.now().microsecondsSinceEpoch}";
    print("IsolateSingleServe ${_topicDoIt}");
    _mainSendPort = _mainReceiver.sendPort;
    _mainSubscription = _mainReceiver.listen((message) async {
      //print("_mainReceiver.listen: $message");
      _insideSendPort = _insideSendPort ?? message[0] as SendPort;
      // use to send data from Main to background to invoke Isolate.spawn ( doInBackground )
      // _insideSendPort come from _mainSendPort.send, from background by ping topic
      String topic = message[1];
      if (topic == _topicPing) return;

      dynamic data = message[2];
      var handleResult = _mapResultHandle[topic];
      if (handleResult != null) {
        await handleResult(data);
      }
      _isDone = true;
      if (_isSendOnce) {
        // to check if next call of doIt can continue to create new isolate
        await _cleanUpToNextDoIt();
      }
    });
  }

  Future<void> _cleanUpToNextDoIt() async {
    if (_mainIsolate != null) {
      _mainIsolate!.kill(priority: Isolate.immediate);
      _mainIsolate = null;
      _insideSendPort = null;
    }
    var insideSubscription = _mapInsideSubscription[_topicDoIt];
    if (insideSubscription != null) {
      await insideSubscription.cancel();
      insideSubscription = null;
      _mapInsideSubscription.remove(_topicDoIt);
    }
    var insideReceiver = _mapInsideReceiver[_topicDoIt];
    if (insideReceiver != null) {
      insideReceiver = null;
      _mapInsideReceiver.remove(_topicDoIt);
    }
    _isDoing = false;
  }

  StreamSubscription? _mainSubscription;
  Isolate? _mainIsolate;
  final ReceivePort _mainReceiver = ReceivePort();

  SendPort? _insideSendPort;
  SendPort? _mainSendPort;

  final Map<String, Future<void> Function(dynamic)?> _mapResultHandle =
  <String, Future<void> Function(dynamic)?>{};

  final Map<String, Future<dynamic> Function(dynamic, Map<String, dynamic>)>
  _mapHandleWithDi =
  <String, Future<dynamic> Function(dynamic, Map<String, dynamic>)>{};

  _createIsolate(
      Future<dynamic> Function(dynamic, Map<String, dynamic>)
      doInBackgroundWithDi,
      Future<Map<String, dynamic>> Function() diBuilder) async {
    _mainIsolate = await Isolate.spawn(_spawnCall,
        [_mainSendPort!, doInBackgroundWithDi, _topicDoIt, diBuilder]);
  }

  _sendData(dynamic data) async {
    while (_insideSendPort == null) {
      await Future.delayed(const Duration(microseconds: 1));
    }
    _insideSendPort!.send([_topicDoIt, data]);
  }

  static final Map<String, StreamSubscription> _mapInsideSubscription =
  <String, StreamSubscription>{};
  static final Map<String, ReceivePort> _mapInsideReceiver =
  <String, ReceivePort>{};

  static _spawnCall(
      dynamic mainSendPort_doInBackgroundWithDi_topic_diBuilder) async {
    SendPort mainSendPort =
    mainSendPort_doInBackgroundWithDi_topic_diBuilder[0];

    Future<dynamic> Function(dynamic, Map<String, dynamic>)
    doInBackgroundWithDi =
    mainSendPort_doInBackgroundWithDi_topic_diBuilder[1];

    var topicDoit = mainSendPort_doInBackgroundWithDi_topic_diBuilder[2];

    Future<Map<String, dynamic>> Function() diBuilder =
    mainSendPort_doInBackgroundWithDi_topic_diBuilder[3];

    Map<String, dynamic> diCollection = await diBuilder();

    var insideReceiver = ReceivePort(topicDoit);
    if (_mapInsideReceiver.containsKey(topicDoit)) {}

    _mapInsideReceiver[topicDoit] = insideReceiver;
    var insideSendPort = insideReceiver.sendPort;

    var insideSubscription = insideReceiver.listen((message) async {
      var topicToProcess = message[0];
      dynamic dataToProcess = message[1];

      var result = await doInBackgroundWithDi(dataToProcess, diCollection);
      mainSendPort.send([insideSendPort, topicToProcess, result]);
    });

    if (_mapInsideSubscription.containsKey(topicDoit)) {}
    _mapInsideSubscription[topicDoit] = insideSubscription;

    mainSendPort.send([
      insideSendPort,
      _topicPing,
      "_insideSendPort forward to main process, to do send data to do in background"
    ]);
  }

  bool isRunning() {
    return _isDoing;
  }

  Future<void> doOnce(
      {required dynamic dataToDo,
        required Future<dynamic> Function(dynamic) doInBackground,
        Future<void> Function(dynamic)? onResult}) async {
    _isSendOnce = true;
    _isDone = false;
    while (_isDoing) {
      await Future.delayed(const Duration(microseconds: 1));
    }
    _isDoing = true;

    diFunc(data, diCollection) async {
      return await doInBackground(data);
    }

    _mapHandleWithDi[_topicDoIt] = diFunc;
    _mapResultHandle[_topicDoIt] = onResult;
    await _createIsolate(diFunc, () async => <String, dynamic>{});
    await _sendData(dataToDo);
  }

  IsolateSingleServe withBackgroundFunction(
      Future<dynamic> Function(dynamic, Map<String, dynamic>)
      doInBackgroundWithDi) {
    if(_isDoing){
      throw Exception("Isolate spawned, in progress do job, can not change. Can call forceClose, can cause lost data is processing");
    }
    _mapHandleWithDi[_topicDoIt] = doInBackgroundWithDi;
    return this;
  }

  IsolateSingleServe withOnResultFunction(
      Future<void> Function(dynamic) onResult) {
    _mapResultHandle[_topicDoIt] = onResult;
    return this;
  }

  Future<IsolateSingleServe> initSendManyTimes(
      {Future<Map<String, dynamic>> Function()? diBuilder}) async {
    _isSendOnce = false;
    var doInBackgroundWithDi = _mapHandleWithDi[_topicDoIt];
    if (doInBackgroundWithDi == null) {
      throw Exception(
          "Not register function: doInBackground, should call withBackgroundFunction");
    }

    _isDoing = true;
    await _createIsolate(
        doInBackgroundWithDi, diBuilder ?? () async => <String, dynamic>{});

    print("initToSendManyDatas, then call sendData many times in need, then HAVE TO call closeToSendManyDatas to release Isolate for other");
    return this;
  }

  Future<void> sendData(dynamic dataToDo) async {
    if(_isSendOnce) {
      throw Exception("If call one times, call function doOnce, To send many time -> Have to call this function first: initToSendManyDatas. "
          "then when done call closeToSendManyDatas to release Isolate for other");
    }
    // else{
    //   var doInBackgroundWithDi = _mapHandleWithDi[_topicDoIt];
    //   if (doInBackgroundWithDi == null) {
    //     throw Exception(
    //         "Not register function: doInBackground, should call withBackgroundFunction");
    //   }
    // }
    await _sendData(dataToDo);
  }

  Future<void> forceClose() async {
    await _cleanUpToNextDoIt();
    _isSendOnce = true;
    _isDoing = false;
  }

  Future<void> closeSendManyTimes() async {
    await forceClose();
  }
}


class IsolatePoolServe {
  static IsolatePoolServe instance = IsolatePoolServe._();

  IsolatePoolServe._() {
    int numOfW=Platform.numberOfProcessors~/2;
    if (numOfW<1) numOfW=1;

    for (var i = 0; i < numOfW; i++) {
      var key = "$i";
      _worker[key] = IsolateSingleServe(topic: key);
    }
    print("Worker IsolatePoolServe: ${_worker.length} worker(s)");

    _timer =
        Timer.periodic(const Duration(microseconds: 1), (timer) async {
          var freeWorkers = _worker.values
              .where((element) => element.isRunning() == false)
              .toList();
          var len = freeWorkers.length;

          for (var i = 0; i < len; i++) {
            if (_pendingDoIt.isNotEmpty) {
              var td = _pendingDoIt.removeFirst();
              if (td != null) {
                dynamic dataToDo = td[0];
                Future<dynamic> Function(dynamic) doInBackground = td[1];
                Future<void> Function(dynamic)? onResult = td[2];
                var worker = freeWorkers[i];
                worker.doOnce(
                    dataToDo: dataToDo,
                    doInBackground: doInBackground,
                    onResult: onResult);
              }
            }
          }
        });
  }

  Timer? _timer;

  final Map<String, IsolateSingleServe> _worker =
  <String, IsolateSingleServe>{};

  final Queue<dynamic> _pendingDoIt = Queue();

  Future<void> doOnce(
      {required dynamic dataToDo,
        required Future<dynamic> Function(dynamic) doInBackground,
        Future<void> Function(dynamic)? onResult}) async {
    _pendingDoIt.add([dataToDo, doInBackground, onResult]);
  }

  Future<IsolateSingleServe> getFeeWorker() async {
    while (true) {
      var temp = _worker.values
          .where((element) => element.isRunning() == false)
          .toList();
      if (temp.isNotEmpty) return temp.first;

      await Future.delayed(const Duration(microseconds: 1));
    }
  }
}

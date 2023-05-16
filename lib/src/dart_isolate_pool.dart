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
    if (_isDoing) {
      throw Exception(
          "Isolate spawned, in progress do job, can not change. Can call forceClose, can cause lost data is processing");
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

    print(
        "initToSendManyDatas, then call sendData many times in need, then HAVE TO call closeToSendManyDatas to release Isolate for other");
    return this;
  }

  Future<void> sendData(dynamic dataToDo) async {
    if (_isSendOnce) {
      throw Exception(
          "If call one times, call function doOnce, To send many time -> Have to call this function first: initToSendManyDatas. "
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
    int numOfW = Platform.numberOfProcessors ~/ 2;
    if (numOfW < 1) numOfW = 1;

    for (var i = 0; i < numOfW; i++) {
      var key = "$i";
      _worker[key] = IsolateSingleServe(topic: key);
    }
    print("Worker IsolatePoolServe: ${_worker.length} worker(s)");

    _timer = Timer.periodic(const Duration(microseconds: 1), (timer) async {
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

class IsolatePubSubServe {
  static IsolatePubSubServe instance =
  IsolatePubSubServe(topicDoIt: "singelton_IsolatePubSubServe");

  String _topicDoIt = "DoIt";
  static const String _topicPing = "____ping____";
  StreamSubscription? _mainSubscription;
  Isolate? _mainIsolate;
  final ReceivePort _mainReceiver = ReceivePort();

  SendPort? _insideSendPort;
  SendPort? _mainSendPort;

  static final Map<String, StreamSubscription> _mapInsideSubscription =
  <String, StreamSubscription>{};
  static final Map<String, ReceivePort> _mapInsideReceiver =
  <String, ReceivePort>{};

  IsolatePubSubServe({String topicDoIt = "DoIt"}) {
    _topicDoIt = "${topicDoIt}_${DateTime.now().microsecondsSinceEpoch}";
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

      Future<void> Function(dynamic, Map<String, String>)? onResult =
      _topicOnResults[topic];

      if (onResult != null) {
        onResult(data, _topicEnvs);
      }
    });

    _timer = Timer.periodic(const Duration(microseconds: 1), (timer) async {
      for (var key in _dataPending.keys) {
        var queue = _dataPending[key];
        if (queue != null && queue.isNotEmpty) {
          var itm = queue.removeFirst();
          _sendData(key, itm);
        }
      }
    });

    _initPublish();
  }

  _sendData(String topic, dynamic data) async {
    while (_insideSendPort == null) {
      await Future.delayed(const Duration(microseconds: 1));
    }
    _insideSendPort!.send([topic, data]);
  }

  Timer? _timer;

  final Map<String,
      Future<dynamic> Function(dynamic, dynamic, Map<String, String>)>
  _topicDoBackgrounds = <String,
      Future<dynamic> Function(dynamic, dynamic, Map<String, String>)>{};

  final Map<String, Future<void> Function(dynamic, Map<String, String>)>
  _topicOnResults =
  <String, Future<void> Function(dynamic, Map<String, String>)>{};

  Map<String, Future<Map<String, dynamic>> Function(Map<String, String>)>
  _topicDiBuilder =
  <String, Future<Map<String, dynamic>> Function(Map<String, String>)>{};

  final Map<String, String> _topicEnvs = <String, String>{};

  static _spawnCall(
      dynamic
      mainSendPort_doInBackgroundWithDi_diBuilder_topicDoIt_envs) async {
    SendPort mainSendPort =
    mainSendPort_doInBackgroundWithDi_diBuilder_topicDoIt_envs[0];

    Map<String, Future<dynamic> Function(dynamic, dynamic, Map<String, String>)>
    doInBackgroundWithDi =
    mainSendPort_doInBackgroundWithDi_diBuilder_topicDoIt_envs[1];

    Map<String, Future<Map<String, dynamic>> Function(Map<String, String>)>
    diBuilder =
    mainSendPort_doInBackgroundWithDi_diBuilder_topicDoIt_envs[2];

    String topicDoit =
    mainSendPort_doInBackgroundWithDi_diBuilder_topicDoIt_envs[3];

    Map<String, String> envs =
    mainSendPort_doInBackgroundWithDi_diBuilder_topicDoIt_envs[4];

    var insideReceiver = ReceivePort(topicDoit);
    if (_mapInsideReceiver.containsKey(topicDoit)) {}

    _mapInsideReceiver[topicDoit] = insideReceiver;
    var insideSendPort = insideReceiver.sendPort;

    Map<String, String> allEnvs = <String, String>{};
    allEnvs.addAll(envs);

    Map<String, Map<String, dynamic>> diCollectionByTopic =
    <String, Map<String, dynamic>>{};

    for (var diFuncKey in diBuilder.keys) {
      var diFunc = diBuilder[diFuncKey];
      if (diFunc != null) {
        diCollectionByTopic[diFuncKey] = await diFunc(allEnvs);
      }
    }

    var insideSubscription = insideReceiver.listen((message) async {
      var topicToProcess = message[0];

      if (topicToProcess == _topicAddNewDoInBackgroundFunction) {
        String topic = message[1];
        Future<dynamic> Function(dynamic, dynamic, Map<String, String>)
        newDoInBgWithDi = message[2];
        doInBackgroundWithDi[topic] = newDoInBgWithDi;
        return;
      }
      if (topicToProcess == _topicAddNewDiBuilder) {
        String topic = message[1];
        Future<Map<String, dynamic>> Function(Map<String, String>)
        newIdBuilder = message[2];
        diCollectionByTopic[topic] = await newIdBuilder(allEnvs);
        return;
      }

      if (topicToProcess == _topicAddNewEnv) {
        String topic = message[1];
        Map<String, String> env = message[2];

        allEnvs.addAll(env);

        return;
      }

      dynamic dataToProcess = message[1];

      var doInBgOfTopic = doInBackgroundWithDi[topicToProcess];
      var diCollection =
      diCollectionByTopic[topicToProcess] ??= <String, dynamic>{};

      //Isolate spawned have own sync context, event loop,
      // try to use async =))) Future do then no wait.
      // hope no block next do
      _doThenSendResultToMainThread(mainSendPort, insideSendPort,
          topicToProcess, dataToProcess, diCollection, allEnvs, doInBgOfTopic!);
    });

    if (_mapInsideSubscription.containsKey(topicDoit)) {}
    _mapInsideSubscription[topicDoit] = insideSubscription;

    mainSendPort.send([
      insideSendPort,
      _topicPing,
      "_insideSendPort forward to main process, to do send data to do in background"
    ]);
  }

  static Future<void> _doThenSendResultToMainThread(
      SendPort cloneMainSendPort,
      SendPort cloneInsideSendport,
      String cloneTopic,
      dynamic cloneData,
      Map<String, dynamic> cloneDiCollection,
      Map<String, String> allEnvs,
      Future<dynamic> Function(dynamic, dynamic, Map<String, String>)
      cloneBgFunc) async {
    var result = await cloneBgFunc(cloneData, cloneDiCollection, allEnvs);

    cloneMainSendPort.send([cloneInsideSendport, cloneTopic, result]);
  }

  final Map<String, Queue<dynamic>> _dataPending = <String, Queue<dynamic>>{};

  /// This function call when need pass data to AddBackgroundFunction.
  /// eg: when user touch button
  /// args data type similar to Isolate sendport support
  Future<void> Publish(String topic, dynamic data) async {
    if (topic.trim() == "") throw Exception("empty topic name");
    if (topic == _topicPing) {
      throw Exception("Invalid topic, should not: $_topicPing");
    }
    if (topic == _topicAddNewDiBuilder) {
      throw Exception("Invalid topic, should not: $_topicAddNewDiBuilder");
    }
    if (topic == _topicAddNewDoInBackgroundFunction) {
      throw Exception(
          "Invalid topic, should not: $_topicAddNewDoInBackgroundFunction");
    }
    await _ensureSpawn();

    if (_isDoing == false) throw Exception("Can not publish cause closed");

    if (_topicDoBackgrounds.keys.any((element) => element == topic) == false) {
      throw Exception("No Subscrier for topic: $topic");
    }

    if (_dataPending[topic] == null) {
      _dataPending[topic] = Queue<dynamic>();
    }
    _dataPending[topic]!.add(data);
  }

  // Future<IsolatePubSubServe> AddBgHandleAndOnResult(
  //     String topic,
  //     Future<dynamic> Function(dynamic, dynamic) doInBackground,
  //     Future<void> Function(dynamic) onMessage) async {
  //   if (topic == _topicPing) {
  //     throw Exception("Invalid topic, should not: $_topicPing");
  //   }
  //
  //   _topicDoBackgrounds[topic] = doInBackground;
  //   _topicOnResults[topic] = onMessage;
  //   return this;
  // }

  static const _topicAddNewDoInBackgroundFunction = "__add_do_in_background__";

  /// Should register in initState, it will called in side Isolate spawn
  /// args from func Publish , support args similar to Isolate sendport
  /// diCollection come from func AddDiBuilderFunction, AddDiBuilderFunction called inside Isolate spawn
  /// [doInBackground:(args, diCollection) async{ return [result]; }]
  Future<IsolatePubSubServe> AddBackgroundFunction(
      String topic,
      Future<dynamic> Function(dynamic, dynamic, Map<String, String>)
      doInBackground) async {
    if (topic.trim() == "") throw Exception("empty topic name");
    if (topic == _topicPing) {
      throw Exception("Invalid topic, should not: $_topicPing");
    }
    if (topic == _topicAddNewDiBuilder) {
      throw Exception("Invalid topic, should not: $_topicAddNewDiBuilder");
    }
    if (topic == _topicAddNewDoInBackgroundFunction) {
      throw Exception(
          "Invalid topic, should not: $_topicAddNewDoInBackgroundFunction");
    }
    if (topic == _topicAddNewEnv) {
      throw Exception("Invalid topic, should not: $_topicAddNewEnv");
    }
    await _ensureSpawn();

    _topicDoBackgrounds[topic] = doInBackground;

    while (_insideSendPort == null) {
      await Future.delayed(const Duration(microseconds: 1));
    }
    _insideSendPort!
        .send([_topicAddNewDoInBackgroundFunction, topic, doInBackground]);

    await Future.delayed(const Duration(seconds: 1));

    return this;
  }

  /// UI thread. This funciton will use to handle result when AddBackgroundFunction done
  /// onMessage:(result) async{ // if mounted setState }
  ///
  Future<IsolatePubSubServe> AddOnResultFunction(String topic,
      Future<void> Function(dynamic, Map<String, String>) onMessage) async {
    if (topic.trim() == "") throw Exception("empty topic name");
    if (topic == _topicPing) {
      throw Exception("Invalid topic, should not: $_topicPing");
    }
    if (topic == _topicAddNewDiBuilder) {
      throw Exception("Invalid topic, should not: $_topicAddNewDiBuilder");
    }
    if (topic == _topicAddNewDoInBackgroundFunction) {
      throw Exception(
          "Invalid topic, should not: $_topicAddNewDoInBackgroundFunction");
    }
    if (topic == _topicAddNewEnv) {
      throw Exception("Invalid topic, should not: $_topicAddNewEnv");
    }
    await _ensureSpawn();

    _topicOnResults[topic] = onMessage;

    return this;
  }

  static const _topicAddNewDiBuilder = "__add_di_builder__";

  /// It will called once to build DI collection, for AddBackgroundFunction reuse collection
  Future<IsolatePubSubServe> AddDiBuilderFunction(
      String topic,
      Future<Map<String, dynamic>> Function(Map<String, String>)
      diBuilder) async {
    if (topic.trim() == "") throw Exception("empty topic name");
    if (topic == _topicPing) {
      throw Exception("Invalid topic, should not: $_topicPing");
    }
    if (topic == _topicAddNewDiBuilder) {
      throw Exception("Invalid topic, should not: $_topicAddNewDiBuilder");
    }
    if (topic == _topicAddNewDoInBackgroundFunction) {
      throw Exception(
          "Invalid topic, should not: $_topicAddNewDoInBackgroundFunction");
    }
    if (topic == _topicAddNewEnv) {
      throw Exception("Invalid topic, should not: $_topicAddNewEnv");
    }
    await _ensureSpawn();

    _topicDiBuilder[topic] = diBuilder;

    while (_insideSendPort == null) {
      await Future.delayed(const Duration(microseconds: 1));
    }
    _insideSendPort!.send([_topicAddNewDiBuilder, topic, diBuilder]);

    await Future.delayed(const Duration(seconds: 1));

    return this;
  }

  static const _topicAddNewEnv = "__add_env__";

  Future<IsolatePubSubServe> AddEnvs(Map<String, String> env) async {
    for (var kenv in _topicEnvs.keys) {
      if (env.containsKey(kenv)) {
        throw Exception("Exist key in envs: $kenv");
      }
    }

    await _ensureSpawn();

    _topicEnvs.addAll(env);

    while (_insideSendPort == null) {
      await Future.delayed(const Duration(microseconds: 1));
    }
    _insideSendPort!.send([_topicAddNewEnv, _topicAddNewEnv, env]);

    await Future.delayed(const Duration(seconds: 1));

    return this;
  }

  _ensureSpawn() async {
    while (_spawned == false) {
      await Future.delayed(const Duration(microseconds: 1));
    }
    while (_insideSendPort == null) {
      await Future.delayed(const Duration(microseconds: 1));
    }
  }

  bool _spawned = false;

  Future<IsolatePubSubServe> _initPublish(
      {Map<String, Future<Map<String, dynamic>> Function(Map<String, String>)>?
      diBuilder}) async {
    if (diBuilder != null) {
      if (diBuilder.keys.any((element) =>
      element == _topicPing ||
          element == _topicAddNewDiBuilder ||
          element == _topicAddNewDoInBackgroundFunction)) {
        throw Exception(
            "Invalid topic, should not: $_topicPing , $_topicAddNewDoInBackgroundFunction ,  $_topicAddNewDiBuilder");
      }
    }

    _isDoing = true;

    _topicDiBuilder = diBuilder ??
        <String, Future<Map<String, dynamic>> Function(Map<String, String>)>{};

    _mainIsolate = await Isolate.spawn(_spawnCall, [
      _mainSendPort!,
      _topicDoBackgrounds,
      _topicDiBuilder,
      _topicDoIt,
      _topicEnvs
    ]);

    _spawned = true;

    print("IsolatePubSubServe: $_topicDoIt ready to use");

    return this;
  }

  bool _isDoing = false;

  Future<void> ClosePublish() async {
    _isDoing = false;
    await _cleanUpToNextDoIt();
    _timer?.cancel();
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
  }
}

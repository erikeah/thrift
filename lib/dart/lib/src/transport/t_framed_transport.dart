/// Licensed to the Apache Software Foundation (ASF) under one
/// or more contributor license agreements. See the NOTICE file
/// distributed with this work for additional information
/// regarding copyright ownership. The ASF licenses this file
/// to you under the Apache License, Version 2.0 (the
/// "License"); you may not use this file except in compliance
/// with the License. You may obtain a copy of the License at
///
/// http://www.apache.org/licenses/LICENSE-2.0
///
/// Unless required by applicable law or agreed to in writing,
/// software distributed under the License is distributed on an
/// "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
/// KIND, either express or implied. See the License for the
/// specific language governing permissions and limitations
/// under the License.

part of thrift;

/// Framed [TTransport].
///
/// Adapted from the Java Framed transport.
class TFramedTransport extends TBufferedTransport {
  static const int headerByteCount = 4;

  final TTransport _transport;

  final Uint8List _headerBytes = Uint8List(headerByteCount);
  int _receivedHeaderBytes = 0;

  int _bodySize = 0;
  Uint8List? _body;
  int _receivedBodyBytes = 0;

  Completer<Uint8List>? _frameCompleter;

  TFramedTransport(TTransport transport)
      : _transport = transport,
        _body = null,
        _frameCompleter = null;

  @override
  bool get isOpen => _transport.isOpen;

  @override
  Future open() {
    _reset(isOpen: true);
    return _transport.open();
  }

  @override
  Future close() {
    _reset(isOpen: false);
    return _transport.close();
  }

  @override
  int read(Uint8List buffer, int offset, int length) {
    if (hasReadData) {
      int got = super.read(buffer, offset, length);
      if (got > 0) return got;
    }

    // IMPORTANT: by the time you've got here,
    // an entire frame is available for reading

    return super.read(buffer, offset, length);
  }

  void _readFrame() {
    if (_body == null) {
      bool gotFullHeader = _readFrameHeader();
      if (!gotFullHeader) {
        return;
      }
    }

    _readFrameBody();
  }

  bool _readFrameHeader() {
    int remainingHeaderBytes = headerByteCount - _receivedHeaderBytes;

    int got = _transport.read(
        _headerBytes, _receivedHeaderBytes, remainingHeaderBytes);
    if (got < 0) {
      throw TTransportError(TTransportErrorType.UNKNOWN,
          "Socket closed during frame header read");
    }

    _receivedHeaderBytes += got;

    if (_receivedHeaderBytes == headerByteCount) {
      int size = _headerBytes.buffer.asByteData().getUint32(0);

      _receivedHeaderBytes = 0;

      if (size < 0) {
        throw TTransportError(
            TTransportErrorType.UNKNOWN, "Read a negative frame size: $size");
      }

      _bodySize = size;
      _body = Uint8List(_bodySize);
      _receivedBodyBytes = 0;

      return true;
    } else {
      _registerForReadableBytes();
      return false;
    }
  }

  void _readFrameBody() {
    var remainingBodyBytes = _bodySize - _receivedBodyBytes;
    if (_body == null) {
      throw TTransportError(
          TTransportErrorType.UNKNOWN, "Null is not a valid value to read");
    }
    int got = _transport.read(_body!, _receivedBodyBytes, remainingBodyBytes);
    if (got < 0) {
      throw TTransportError(
          TTransportErrorType.UNKNOWN, "Socket closed during frame body read");
    }

    _receivedBodyBytes += got;

    if (_receivedBodyBytes == _bodySize) {
      var body = _body!;

      _bodySize = 0;
      _body = null;
      _receivedBodyBytes = 0;

      _setReadBuffer(body);

      if (_frameCompleter == null) {
        throw TTransportError(TTransportErrorType.UNKNOWN,
            "Unexpected Null value, request cannot be satisfied");
      }
      Completer<Uint8List> completer = _frameCompleter!;
      _frameCompleter = null;
      completer.complete(Uint8List(0));
    } else {
      _registerForReadableBytes();
    }
  }

  @override
  Future flush() {
    if (_frameCompleter == null) {
      Uint8List buffer = consumeWriteBuffer();
      int length = buffer.length;

      _headerBytes.buffer.asByteData().setUint32(0, length);
      _transport.write(_headerBytes, 0, headerByteCount);
      _transport.write(buffer, 0, length);

      _frameCompleter = Completer<Uint8List>();
      _registerForReadableBytes();
    }

    return _frameCompleter!.future;
  }

  void _registerForReadableBytes() {
    _transport.flush().then((_) {
      _readFrame();
    }).catchError((e) {
      if (_frameCompleter == null) {
        throw TTransportError(TTransportErrorType.UNKNOWN,
            "Unexpected Null value, request cannot be satisfied");
      }
      Completer<Uint8List> completer = _frameCompleter!;

      _receivedHeaderBytes = 0;
      _bodySize = 0;
      _body = null;
      _receivedBodyBytes = 0;
      _frameCompleter = null;

      completer.completeError(e);
    });
  }
}

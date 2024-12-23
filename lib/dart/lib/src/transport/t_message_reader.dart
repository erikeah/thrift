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

/// [TMessageReader] extracts a [TMessage] from bytes.  This is used to allow a
/// transport to inspect the message seqid and map responses to requests.
class TMessageReader {
  final TProtocolFactory protocolFactory;

  final int byteOffset;
  final _TMessageReaderTransport _transport;

  /// Construct a [MessageReader].  The optional [byteOffset] specifies the
  /// number of bytes to skip before reading the [TMessage].
  TMessageReader(this.protocolFactory, {int byteOffset = 0})
      : _transport = _TMessageReaderTransport(),
        this.byteOffset = byteOffset;

  TMessage readMessage(Uint8List bytes) {
    _transport.reset(bytes, byteOffset);
    TProtocol protocol = protocolFactory.getProtocol(_transport);
    TMessage message = protocol.readMessageBegin();
    _transport.reset(Uint8List(0));

    return message;
  }
}

/// An internal class used to support [TMessageReader].
class _TMessageReaderTransport extends TTransport {
  late Iterator<int> _readIterator;

  void reset(Uint8List bytes, [int offset = 0]) {
    if (offset > bytes.length) {
      throw ArgumentError("The offset exceeds the bytes length");
    }

    _readIterator = bytes.iterator;

    for (var i = 0; i < offset; i++) {
      _readIterator.moveNext();
    }
  }

  @override
  get isOpen => true;

  @override
  Future open() => throw UnsupportedError("Unsupported in MessageReader");

  @override
  Future close() => throw UnsupportedError("Unsupported in MessageReader");

  @override
  int read(Uint8List buffer, int offset, int length) {
    if (offset + length > buffer.length) {
      throw ArgumentError("The range exceeds the buffer length");
    }

    if (length <= 0) {
      return 0;
    }

    int i = 0;
    while (i < length && _readIterator.moveNext()) {
      buffer[offset + i] = _readIterator.current;
      i++;
    }

    return i;
  }

  @override
  void write(Uint8List buffer, int offset, int length) =>
      throw UnsupportedError("Unsupported in MessageReader");

  @override
  Future flush() => throw UnsupportedError("Unsupported in MessageReader");
}

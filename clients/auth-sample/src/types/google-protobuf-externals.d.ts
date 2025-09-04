declare module 'google-protobuf/google/protobuf/empty_pb' {
  export class Empty {
    constructor();
    serializeBinary(): Uint8Array;
    static deserializeBinary(bytes: Uint8Array): Empty;
  }
}



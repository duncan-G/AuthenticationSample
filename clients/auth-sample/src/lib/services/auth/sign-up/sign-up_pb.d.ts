import * as jspb from 'google-protobuf'

import * as google_protobuf_empty_pb from 'google-protobuf/google/protobuf/empty_pb'; // proto import: "google/protobuf/empty.proto"


export class InitiateSignUpRequest extends jspb.Message {
  getEmailAddress(): string;
  setEmailAddress(value: string): InitiateSignUpRequest;

  getPassword(): string;
  setPassword(value: string): InitiateSignUpRequest;
  hasPassword(): boolean;
  clearPassword(): InitiateSignUpRequest;

  serializeBinary(): Uint8Array;
  toObject(includeInstance?: boolean): InitiateSignUpRequest.AsObject;
  static toObject(includeInstance: boolean, msg: InitiateSignUpRequest): InitiateSignUpRequest.AsObject;
  static serializeBinaryToWriter(message: InitiateSignUpRequest, writer: jspb.BinaryWriter): void;
  static deserializeBinary(bytes: Uint8Array): InitiateSignUpRequest;
  static deserializeBinaryFromReader(message: InitiateSignUpRequest, reader: jspb.BinaryReader): InitiateSignUpRequest;
}

export namespace InitiateSignUpRequest {
  export type AsObject = {
    emailAddress: string,
    password?: string,
  }

  export enum PasswordCase { 
    _PASSWORD_NOT_SET = 0,
    PASSWORD = 2,
  }
}

export class VerifyAndSignUpRequest extends jspb.Message {
  getEmailAddress(): string;
  setEmailAddress(value: string): VerifyAndSignUpRequest;

  getName(): string;
  setName(value: string): VerifyAndSignUpRequest;

  getVerificationCode(): string;
  setVerificationCode(value: string): VerifyAndSignUpRequest;

  serializeBinary(): Uint8Array;
  toObject(includeInstance?: boolean): VerifyAndSignUpRequest.AsObject;
  static toObject(includeInstance: boolean, msg: VerifyAndSignUpRequest): VerifyAndSignUpRequest.AsObject;
  static serializeBinaryToWriter(message: VerifyAndSignUpRequest, writer: jspb.BinaryWriter): void;
  static deserializeBinary(bytes: Uint8Array): VerifyAndSignUpRequest;
  static deserializeBinaryFromReader(message: VerifyAndSignUpRequest, reader: jspb.BinaryReader): VerifyAndSignUpRequest;
}

export namespace VerifyAndSignUpRequest {
  export type AsObject = {
    emailAddress: string,
    name: string,
    verificationCode: string,
  }
}

export class IsEmailTakenRequest extends jspb.Message {
  getEmailAddress(): string;
  setEmailAddress(value: string): IsEmailTakenRequest;

  serializeBinary(): Uint8Array;
  toObject(includeInstance?: boolean): IsEmailTakenRequest.AsObject;
  static toObject(includeInstance: boolean, msg: IsEmailTakenRequest): IsEmailTakenRequest.AsObject;
  static serializeBinaryToWriter(message: IsEmailTakenRequest, writer: jspb.BinaryWriter): void;
  static deserializeBinary(bytes: Uint8Array): IsEmailTakenRequest;
  static deserializeBinaryFromReader(message: IsEmailTakenRequest, reader: jspb.BinaryReader): IsEmailTakenRequest;
}

export namespace IsEmailTakenRequest {
  export type AsObject = {
    emailAddress: string,
  }
}

export class IsEmailTakenReply extends jspb.Message {
  getTaken(): boolean;
  setTaken(value: boolean): IsEmailTakenReply;

  serializeBinary(): Uint8Array;
  toObject(includeInstance?: boolean): IsEmailTakenReply.AsObject;
  static toObject(includeInstance: boolean, msg: IsEmailTakenReply): IsEmailTakenReply.AsObject;
  static serializeBinaryToWriter(message: IsEmailTakenReply, writer: jspb.BinaryWriter): void;
  static deserializeBinary(bytes: Uint8Array): IsEmailTakenReply;
  static deserializeBinaryFromReader(message: IsEmailTakenReply, reader: jspb.BinaryReader): IsEmailTakenReply;
}

export namespace IsEmailTakenReply {
  export type AsObject = {
    taken: boolean,
  }
}


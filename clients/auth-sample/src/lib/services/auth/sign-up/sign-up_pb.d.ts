import * as jspb from 'google-protobuf'

import * as google_protobuf_empty_pb from 'google-protobuf/google/protobuf/empty_pb'; // proto import: "google/protobuf/empty.proto"


export class InitiateSignUpRequest extends jspb.Message {
  getEmailAddress(): string;
  setEmailAddress(value: string): InitiateSignUpRequest;

  getRequirePassword(): boolean;
  setRequirePassword(value: boolean): InitiateSignUpRequest;

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
    requirePassword: boolean,
    password?: string,
  }

  export enum PasswordCase { 
    _PASSWORD_NOT_SET = 0,
    PASSWORD = 3,
  }
}

export class InitiateSignUpResponse extends jspb.Message {
  getNextStep(): SignUpStep;
  setNextStep(value: SignUpStep): InitiateSignUpResponse;

  serializeBinary(): Uint8Array;
  toObject(includeInstance?: boolean): InitiateSignUpResponse.AsObject;
  static toObject(includeInstance: boolean, msg: InitiateSignUpResponse): InitiateSignUpResponse.AsObject;
  static serializeBinaryToWriter(message: InitiateSignUpResponse, writer: jspb.BinaryWriter): void;
  static deserializeBinary(bytes: Uint8Array): InitiateSignUpResponse;
  static deserializeBinaryFromReader(message: InitiateSignUpResponse, reader: jspb.BinaryReader): InitiateSignUpResponse;
}

export namespace InitiateSignUpResponse {
  export type AsObject = {
    nextStep: SignUpStep,
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

export enum SignUpStep { 
  UNSPECIFIED = 0,
  PASSWORD_REQUIRED = 1,
  VERIFICATION_REQUIRED = 2,
}

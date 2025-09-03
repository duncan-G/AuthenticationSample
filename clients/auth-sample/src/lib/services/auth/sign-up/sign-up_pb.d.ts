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

export class VerifyAndSignInRequest extends jspb.Message {
  getEmailAddress(): string;
  setEmailAddress(value: string): VerifyAndSignInRequest;

  getName(): string;
  setName(value: string): VerifyAndSignInRequest;

  getVerificationCode(): string;
  setVerificationCode(value: string): VerifyAndSignInRequest;

  serializeBinary(): Uint8Array;
  toObject(includeInstance?: boolean): VerifyAndSignInRequest.AsObject;
  static toObject(includeInstance: boolean, msg: VerifyAndSignInRequest): VerifyAndSignInRequest.AsObject;
  static serializeBinaryToWriter(message: VerifyAndSignInRequest, writer: jspb.BinaryWriter): void;
  static deserializeBinary(bytes: Uint8Array): VerifyAndSignInRequest;
  static deserializeBinaryFromReader(message: VerifyAndSignInRequest, reader: jspb.BinaryReader): VerifyAndSignInRequest;
}

export namespace VerifyAndSignInRequest {
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

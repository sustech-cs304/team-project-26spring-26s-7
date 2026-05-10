/*
 * Copyright (c) 2024 Huawei Device Co., Ltd.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 */

import { common, errorManager } from '@kit.AbilityKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { logger } from './Logger';

const TAG = 'CrashReporter';
const CRASH_LOG_FILE = 'crashes.log';
const MAX_LOG_BYTES = 256 * 1024;

/**
 * 应用崩溃 / 未捕获异常的本地日志收集。
 *
 * 设计：
 *  - 写入沙箱 filesDir/crashes.log，单文件硬上限 256 KB（超出截断）
 *  - 不依赖网络，不上报第三方
 *  - 启动时可读取上次会话的崩溃，提示用户上报或反馈
 *
 * AppGallery 审核要求应用具备崩溃捕获能力，本地落盘是最低基线。
 * 后续接入 AGConnect 崩溃分析服务时再统一上报。
 */
export class CrashReporter {
  private static observerId: number = -1;
  private static logPath: string = '';
  private static initialized: boolean = false;

  static init(context: common.UIAbilityContext): void {
    if (CrashReporter.initialized) {
      return;
    }
    CrashReporter.logPath = `${context.filesDir}/${CRASH_LOG_FILE}`;
    try {
      CrashReporter.observerId = errorManager.on('error', {
        onUnhandledException: (errMsg: string) => {
          CrashReporter.appendLog('unhandledException', errMsg, '');
        },
        onException: (errorObj: Error) => {
          CrashReporter.appendLog('exception', errorObj.message ?? '', errorObj.stack ?? '');
        }
      });
      CrashReporter.initialized = true;
      logger.info(TAG, `CrashReporter initialized, observerId=${CrashReporter.observerId}, logPath=${CrashReporter.logPath}`);
    } catch (err) {
      logger.error(TAG, `CrashReporter init failed: ${JSON.stringify(err)}`);
    }
  }

  static teardown(): void {
    if (CrashReporter.observerId >= 0) {
      try {
        errorManager.off('error', CrashReporter.observerId);
      } catch (_) {}
      CrashReporter.observerId = -1;
    }
    CrashReporter.initialized = false;
  }

  /** 业务侧主动记录非致命异常 */
  static recordError(tag: string, message: string, stack?: string): void {
    CrashReporter.appendLog(`recorded:${tag}`, message, stack ?? '');
  }

  /** 读取已记录的崩溃日志 */
  static readLog(): string {
    if (CrashReporter.logPath.length === 0) {
      return '';
    }
    try {
      if (!fs.accessSync(CrashReporter.logPath)) {
        return '';
      }
      const file = fs.openSync(CrashReporter.logPath, fs.OpenMode.READ_ONLY);
      try {
        const stat = fs.statSync(file.fd);
        const buf = new ArrayBuffer(stat.size);
        fs.readSync(file.fd, buf);
        return new util.TextDecoder('utf-8').decodeWithStream(new Uint8Array(buf));
      } finally {
        fs.closeSync(file);
      }
    } catch (err) {
      logger.error(TAG, `readLog failed: ${JSON.stringify(err)}`);
      return '';
    }
  }

  static clearLog(): void {
    if (CrashReporter.logPath.length === 0) {
      return;
    }
    try {
      if (fs.accessSync(CrashReporter.logPath)) {
        fs.unlinkSync(CrashReporter.logPath);
      }
    } catch (err) {
      logger.error(TAG, `clearLog failed: ${JSON.stringify(err)}`);
    }
  }

  private static appendLog(kind: string, message: string, stack: string): void {
    if (CrashReporter.logPath.length === 0) {
      return;
    }
    try {
      const ts = new Date().toISOString();
      const entry = `[${ts}] ${kind}: ${message}\n${stack.length > 0 ? stack + '\n' : ''}---\n`;

      let existing = '';
      try {
        if (fs.accessSync(CrashReporter.logPath)) {
          const file = fs.openSync(CrashReporter.logPath, fs.OpenMode.READ_ONLY);
          try {
            const stat = fs.statSync(file.fd);
            const buf = new ArrayBuffer(stat.size);
            fs.readSync(file.fd, buf);
            existing = new util.TextDecoder('utf-8').decodeWithStream(new Uint8Array(buf));
          } finally {
            fs.closeSync(file);
          }
        }
      } catch (_) {}

      let combined = existing + entry;
      if (combined.length > MAX_LOG_BYTES) {
        combined = combined.substring(combined.length - MAX_LOG_BYTES);
      }

      const writeFile = fs.openSync(
        CrashReporter.logPath,
        fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC
      );
      try {
        fs.writeSync(writeFile.fd, combined);
      } finally {
        fs.closeSync(writeFile);
      }
    } catch (err) {
      logger.error(TAG, `appendLog failed: ${JSON.stringify(err)}`);
    }
  }
}

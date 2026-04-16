/*
 * Copyright (c) 2024 Huawei Device Co., Ltd.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

/**
 * 简易日志工具类
 *
 * ---
 * 说明：这是一个占位实现，用于 data/ 目录下的 Repository 类
 * 队友完成后可替换为完整的 Logger 实现
 * ---
 */

export class Logger {
  info(tag: string, msg: string): void {
    console.info(`${tag}: ${msg}`);
  }

  debug(tag: string, msg: string): void {
    console.debug(`${tag}: ${msg}`);
  }

  warn(tag: string, msg: string): void {
    console.warn(`${tag}: ${msg}`);
  }

  error(tag: string, msg: string): void {
    console.error(`${tag}: ${msg}`);
  }
}

export const logger = new Logger();

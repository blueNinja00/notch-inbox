// Notch Inbox Link: reading whole emails.
// Gmail's "Show original" page holds an email exactly as it arrived (RFC 822 / MIME).
// These helpers find that text, decode it (multipart, base64, quoted-printable, charsets)
// and keep what the notch shows: the HTML or plain-text body, small inline images and the
// names of attachments. Nothing in this file talks to the network.

(function (root) {
  'use strict';

  const LIMITS = {
    inlineImage: 400 * 1024, // base64 characters per inline image
    inlineTotal: 1500 * 1024, // base64 characters of inline images per email
    html: 2 * 1024 * 1024, // characters of HTML
    text: 300 * 1024, // characters of plain text
    depth: 12, // nested multiparts
  };

  // ---- Gmail's pages ---------------------------------------------------------------------

  /** The raw email inside Gmail's "Show original" page, or null. */
  function rawFromShowOriginal(page) {
    if (typeof page !== 'string') return null;
    const pre = /<pre\b[^>]*raw_message_text[^>]*>([\s\S]*?)<\/pre>/i.exec(page);
    if (!pre) return null;
    // The email is HTML-escaped inside the <pre>; anything tag-like is page markup.
    const raw = decodeEntities(pre[1].replace(/<[^>]*>/g, '')).replace(/^\s+/, '');
    return /^[A-Za-z0-9-]+:/.test(raw) ? raw : null;
  }

  /** Gmail's key for an account ("ik"), which "Show original" may need, from the Gmail page. */
  function ikFromGmailPage(page) {
    if (typeof page !== 'string') return null;
    const globals = arrayItemsAfter(page, 'GLOBALS=');
    const fromGlobals = globals ? unquote(globals[9]) : null;
    if (isIk(fromGlobals)) return fromGlobals;
    const patterns = [/[?&;]ik=([0-9a-f]{6,16})(?![0-9a-z])/i, /["']ik["']\s*:\s*["']([0-9a-f]{6,16})["']/i];
    for (const pattern of patterns) {
      const match = pattern.exec(page);
      if (match) return match[1];
    }
    return null;
  }

  function isIk(value) {
    return typeof value === 'string' && /^[0-9a-f]{6,16}$/i.test(value);
  }

  // The top-level items of the array literal right after `marker`, as source text.
  function arrayItemsAfter(text, marker) {
    const at = text.indexOf(marker);
    if (at < 0) return null;
    const start = text.indexOf('[', at + marker.length);
    if (start < 0 || start - (at + marker.length) > 2) return null;
    const items = [];
    let depth = 0;
    let quote = '';
    let escaped = false;
    let itemStart = start + 1;
    const end = Math.min(text.length, start + 500000);
    for (let i = start; i < end; i += 1) {
      const c = text[i];
      if (quote) {
        if (escaped) escaped = false;
        else if (c === '\\') escaped = true;
        else if (c === quote) quote = '';
      } else if (c === '"' || c === "'") {
        quote = c;
      } else if (c === '[' || c === '{') {
        depth += 1;
      } else if (c === ']' || c === '}') {
        depth -= 1;
        if (depth === 0) {
          items.push(text.slice(itemStart, i).trim());
          return items;
        }
      } else if (c === ',' && depth === 1) {
        items.push(text.slice(itemStart, i).trim());
        itemStart = i + 1;
      }
    }
    return null;
  }

  function unquote(item) {
    if (typeof item !== 'string') return null;
    const match = /^(["'])([\s\S]*)\1$/.exec(item);
    return match ? match[2] : null;
  }

  /** A message's ID both ways: decimal (the feed's <id>) and hex (its link's message_id). */
  function messageIds(id, link) {
    let decimal = null;
    let hex = null;
    const tail = String(id || '').split(':').pop();
    if (/^\d{6,24}$/.test(tail)) decimal = tail;
    const fromLink = /[?&]message_id=([0-9a-f]{6,20})(?![0-9a-z])/i.exec(String(link || ''));
    if (fromLink) hex = fromLink[1].toLowerCase();
    try {
      if (!decimal && hex) decimal = BigInt(`0x${hex}`).toString(10);
      if (!hex && decimal) hex = BigInt(decimal).toString(16);
    } catch (error) {
      return null;
    }
    return decimal ? { decimal, hex } : null;
  }

  // ---- MIME ------------------------------------------------------------------------------

  /** Pulls the readable parts out of a raw email. */
  function parse(raw) {
    const found = { html: null, text: null, inline: {}, attachments: [] };
    collect(parsePart(String(raw).replace(/\r\n?/g, '\n'), 0), found);
    return found;
  }

  function parsePart(source, depth) {
    let headerText = '';
    let body = '';
    if (source.startsWith('\n')) {
      body = source.slice(1); // no headers at all
    } else {
      const blank = source.indexOf('\n\n');
      headerText = blank >= 0 ? source.slice(0, blank) : source;
      body = blank >= 0 ? source.slice(blank + 2) : '';
    }
    const headers = parseHeaders(headerText);
    const contentType = parseValue(headers['content-type'] || 'text/plain');
    const part = {
      headers,
      type: contentType.value.toLowerCase() || 'text/plain',
      params: contentType.params,
      body,
      parts: [],
    };
    if (part.type.startsWith('multipart/') && part.params.boundary && depth < LIMITS.depth) {
      part.parts = splitMultipart(body, part.params.boundary).map((child) => parsePart(child, depth + 1));
    }
    return part;
  }

  function parseHeaders(text) {
    const headers = Object.create(null);
    let name = null;
    for (const line of text.split('\n')) {
      if (/^[ \t]/.test(line)) {
        if (name) headers[name] += ` ${line.trim()}`;
        continue;
      }
      const colon = line.indexOf(':');
      if (colon <= 0) {
        name = null;
        continue;
      }
      const key = line.slice(0, colon).trim().toLowerCase();
      if (key in headers) {
        name = null; // the first copy of a header wins
        continue;
      }
      headers[key] = line.slice(colon + 1).trim();
      name = key;
    }
    return headers;
  }

  // "text/html; charset=utf-8" → { value: 'text/html', params: { charset: 'utf-8' } },
  // including RFC 2231 forms such as filename*=utf-8''r%C3%A9sum%C3%A9.pdf.
  function parseValue(header) {
    const pieces = splitParams(String(header || ''));
    const value = (pieces.shift() || '').trim();
    const params = Object.create(null);
    const segments = Object.create(null);
    for (const piece of pieces) {
      const eq = piece.indexOf('=');
      if (eq <= 0) continue;
      const key = piece.slice(0, eq).trim().toLowerCase();
      let text = piece.slice(eq + 1).trim();
      if (text.length >= 2 && text.startsWith('"') && text.endsWith('"')) {
        text = text.slice(1, -1).replace(/\\(.)/g, '$1');
      }
      const form = /^([^*]+)(?:\*(\d+))?(\*)?$/.exec(key);
      if (!form) continue;
      const [, base, index, encoded] = form;
      const segment = { index: index === undefined ? -1 : Number(index), text, encoded: Boolean(encoded) };
      (segments[base] = segments[base] || []).push(segment);
    }
    for (const base of Object.keys(segments)) {
      const all = segments[base];
      // name*=… beats name*0…, which beats a plain name=…
      const extended = all.find((part) => part.index === -1 && part.encoded);
      const numbered = all.filter((part) => part.index >= 0).sort((a, b) => a.index - b.index);
      const plain = all.find((part) => part.index === -1 && !part.encoded);
      const parts = extended ? [extended] : numbered.length > 0 ? numbered : [plain];
      if (!parts.some((part) => part.encoded)) {
        params[base] = parts.map((part) => part.text).join('');
        continue;
      }
      let charset = 'utf-8';
      let escaped = '';
      parts.forEach((part, i) => {
        let text = part.text;
        if (part.encoded && i === 0) {
          const declared = /^([^']*)'[^']*'([\s\S]*)$/.exec(text);
          if (declared) {
            charset = declared[1] || charset;
            text = declared[2];
          }
        }
        escaped += part.encoded ? text : text.replace(/%/g, '%25');
      });
      params[base] = bytesToText(percentToBytes(escaped), charset);
    }
    return { value, params };
  }

  function splitParams(header) {
    const pieces = [];
    let current = '';
    let quoted = false;
    for (let i = 0; i < header.length; i += 1) {
      const c = header[i];
      if (c === '"' && header[i - 1] !== '\\') quoted = !quoted;
      if (c === ';' && !quoted) {
        pieces.push(current);
        current = '';
      } else {
        current += c;
      }
    }
    pieces.push(current);
    return pieces;
  }

  function splitMultipart(body, boundary) {
    const open = `--${boundary}`;
    const close = `${open}--`;
    const parts = [];
    let current = null;
    for (const line of body.split('\n')) {
      const trimmed = line.replace(/[ \t]+$/, '');
      if (trimmed === close) break;
      if (trimmed === open) {
        if (current) parts.push(current.join('\n'));
        current = [];
      } else if (current) {
        current.push(line);
      }
    }
    if (current) parts.push(current.join('\n'));
    return parts;
  }

  function collect(part, found) {
    if (part.parts.length > 0) {
      if (part.type === 'multipart/alternative') {
        // The last alternative is the richest: prefer HTML, then plain text.
        const richestFirst = part.parts.slice().reverse();
        const chosen = richestFirst.find((child) => contains(child, 'text/html'))
          || richestFirst.find((child) => contains(child, 'text/plain'))
          || richestFirst[0];
        collect(chosen, found);
        if (found.text === null) {
          const plain = part.parts.find((child) => child.type === 'text/plain');
          if (plain) found.text = textOf(plain);
        }
        return;
      }
      part.parts.forEach((child) => collect(child, found));
      return;
    }

    const disposition = parseValue(part.headers['content-disposition'] || '');
    const isAttachment = disposition.value.toLowerCase() === 'attachment';
    const filename = disposition.params.filename || part.params.name || null;

    if (!isAttachment && !filename && (part.type === 'text/html' || part.type === 'text/plain')) {
      const key = part.type === 'text/html' ? 'html' : 'text';
      if (found[key] === null) found[key] = textOf(part);
      return;
    }
    const contentID = part.headers['content-id'];
    if (contentID && part.type.startsWith('image/')) {
      const uri = dataURI(part);
      if (uri) found.inline[contentID.trim().replace(/^<|>$/g, '')] = uri;
      if (!isAttachment) return;
    }
    if (filename || isAttachment || part.type === 'message/rfc822') {
      found.attachments.push(decodeWords(filename || (part.type === 'message/rfc822' ? 'Forwarded email' : 'Attachment')));
    }
  }

  function contains(part, type) {
    return part.type === type || part.parts.some((child) => contains(child, type));
  }

  function transferEncoding(part) {
    return String(part.headers['content-transfer-encoding'] || '7bit').trim().toLowerCase();
  }

  // Bytes for base64 and quoted-printable bodies. 7bit/8bit bodies are already text
  // (Gmail's page decoded them), so those return null.
  function bodyBytes(part) {
    const encoding = transferEncoding(part);
    if (encoding === 'base64') return base64ToBytes(part.body);
    if (encoding === 'quoted-printable') return qpToBytes(part.body);
    return null;
  }

  function textOf(part) {
    const bytes = bodyBytes(part);
    return bytes ? bytesToText(bytes, part.params.charset) : part.body;
  }

  function dataURI(part) {
    if (!/^image\/[a-z0-9.+-]+$/.test(part.type)) return null;
    let base64;
    if (transferEncoding(part) === 'base64') {
      base64 = part.body.replace(/[^A-Za-z0-9+/=]/g, '');
    } else {
      const bytes = bodyBytes(part);
      if (!bytes) return null;
      base64 = bytesToBase64(bytes);
    }
    if (!base64 || base64.length > LIMITS.inlineImage) return null;
    return `data:${part.type};base64,${base64}`;
  }

  // ---- Byte and text decoding ------------------------------------------------------------

  function base64ToBytes(text) {
    let clean = String(text).replace(/[^A-Za-z0-9+/]/g, '');
    if (clean.length % 4 === 1) clean = clean.slice(0, -1);
    while (clean.length % 4) clean += '=';
    const binary = atob(clean);
    const bytes = new Uint8Array(binary.length);
    for (let i = 0; i < binary.length; i += 1) bytes[i] = binary.charCodeAt(i);
    return bytes;
  }

  function bytesToBase64(bytes) {
    let binary = '';
    for (let i = 0; i < bytes.length; i += 1) binary += String.fromCharCode(bytes[i]);
    return btoa(binary);
  }

  function qpToBytes(text) {
    const source = String(text).replace(/=[ \t]*\n/g, ''); // soft line breaks
    const bytes = [];
    const encoder = new TextEncoder();
    for (let i = 0; i < source.length; i += 1) {
      const code = source.charCodeAt(i);
      const hex = source.slice(i + 1, i + 3);
      if (code === 61 && /^[0-9A-Fa-f]{2}$/.test(hex)) {
        bytes.push(parseInt(hex, 16));
        i += 2;
      } else if (code < 128) {
        bytes.push(code);
      } else {
        // A character Gmail's page already decoded: keep it as UTF-8.
        const char = String.fromCodePoint(source.codePointAt(i));
        if (char.length === 2) i += 1;
        encoder.encode(char).forEach((byte) => bytes.push(byte));
      }
    }
    return Uint8Array.from(bytes);
  }

  function percentToBytes(text) {
    const bytes = [];
    const encoder = new TextEncoder();
    for (let i = 0; i < text.length; i += 1) {
      const hex = text.slice(i + 1, i + 3);
      if (text[i] === '%' && /^[0-9A-Fa-f]{2}$/.test(hex)) {
        bytes.push(parseInt(hex, 16));
        i += 2;
      } else {
        encoder.encode(text[i]).forEach((byte) => bytes.push(byte));
      }
    }
    return Uint8Array.from(bytes);
  }

  function bytesToText(bytes, charset) {
    const label = String(charset || 'utf-8').trim().replace(/^"|"$/g, '').toLowerCase();
    for (const candidate of [label, 'utf-8']) {
      try {
        return new TextDecoder(candidate).decode(bytes);
      } catch (error) {
        // Unknown charset: try the next one.
      }
    }
    return Array.from(bytes, (byte) => String.fromCharCode(byte)).join('');
  }

  const NAMED = { lt: '<', gt: '>', amp: '&', quot: '"', apos: "'", nbsp: ' ' };

  function decodeEntities(text) {
    return text.replace(/&(#[xX][0-9a-fA-F]+|#\d+|[a-zA-Z]+);/g, (match, name) => {
      if (name[0] === '#') {
        const hex = name[1] === 'x' || name[1] === 'X';
        const code = parseInt(name.slice(hex ? 2 : 1), hex ? 16 : 10);
        return Number.isFinite(code) && code > 0 && code <= 0x10ffff ? String.fromCodePoint(code) : match;
      }
      const value = NAMED[name.toLowerCase()];
      return value === undefined ? match : value;
    });
  }

  // RFC 2047 encoded words, e.g. =?UTF-8?B?...?= in attachment names.
  function decodeWords(text) {
    return String(text)
      .replace(/(=\?[^?\s]+\?[bBqQ]\?[^?\s]*\?=)\s+(?==\?)/g, '$1')
      .replace(/=\?([^?\s]+)\?([bBqQ])\?([^?\s]*)\?=/g, (match, charset, encoding, data) => {
        try {
          const bytes = encoding.toUpperCase() === 'B' ? base64ToBytes(data) : qpToBytes(data.replace(/_/g, ' '));
          return bytesToText(bytes, charset.split('*')[0]);
        } catch (error) {
          return match;
        }
      });
  }

  // ---- What goes to the app --------------------------------------------------------------

  /** The parts of a parsed email the notch needs, kept to a sensible size. */
  function forApp(found) {
    let html = found.html;
    if (html) {
      let budget = LIMITS.inlineTotal;
      html = html.replace(/(["'(=]\s*)cid:([^"'()\s>]+)/gi, (match, before, id) => {
        let uri = found.inline[id];
        if (!uri) {
          try {
            uri = found.inline[decodeURIComponent(id)];
          } catch (error) {
            uri = undefined;
          }
        }
        if (!uri || uri.length > budget) return match;
        budget -= uri.length;
        return before + uri;
      });
      if (html.length > LIMITS.html || !/\S/.test(html)) html = null;
    }
    let text = found.text;
    if (text && text.length > LIMITS.text) text = `${text.slice(0, LIMITS.text)}\n\n[…]`;
    if (text !== null && !/\S/.test(text)) text = null;
    if (!html && !text) return { error: 'The email has no text to show.' };
    return { html: html || null, text: text || null, attachments: found.attachments.slice(0, 20) };
  }

  const api = { rawFromShowOriginal, ikFromGmailPage, messageIds, parse, forApp, decodeEntities, decodeWords, LIMITS };
  root.NotchMime = api;
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
})(typeof self !== 'undefined' ? self : globalThis);

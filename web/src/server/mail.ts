/**
 * Transactional email, through Resend's HTTP API.
 *
 * Called with `fetch` rather than the SDK: the SDK pulls in Node built-ins that
 * a Worker only has behind a compatibility flag, and the entire surface used
 * here is one POST. A dependency that exists to save eight lines is not worth
 * the platform risk.
 *
 * Two kinds of message, both of which someone is waiting on with the tab still
 * open: confirm your address, and reset your password. Neither is marketing, and
 * neither should read like it.
 */

import type { Env } from "./env.js";

const RESEND_ENDPOINT = "https://api.resend.com/emails";

export interface Message {
  to: string;
  subject: string;
  html: string;
  text: string;
}

export async function sendMail(env: Env, message: Message): Promise<void> {
  const response = await fetch(RESEND_ENDPOINT, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${env.RESEND_API_KEY}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      from: env.MAIL_FROM,
      to: [message.to],
      subject: message.subject,
      html: message.html,
      text: message.text,
    }),
  });

  if (!response.ok) {
    // Thrown rather than swallowed. A sign-up that silently fails to send its
    // verification looks to the person like the account simply does not work,
    // and there is nothing in any log to explain it.
    const detail = await response.text().catch(() => "");
    throw new Error(`Resend refused the message (${response.status}): ${detail}`);
  }
}

/**
 * One plain layout for both messages.
 *
 * A transactional email is read in two seconds inside a client that will mangle
 * anything clever, so it is a sentence, a link, and the same link in full for
 * people whose client eats buttons.
 */
function layout(heading: string, body: string, action: string, url: string): string {
  return `<!doctype html>
<html><body style="margin:0;padding:24px;background:#E9DFC9;font-family:-apple-system,Segoe UI,system-ui,sans-serif;color:#2B2519">
  <div style="max-width:520px;margin:0 auto;background:#FFFCF5;border:1px solid #D8C6A2;border-radius:18px;padding:28px">
    <h1 style="margin:0 0 12px;font-size:22px;font-weight:600;color:#2B2519">${heading}</h1>
    <p style="margin:0 0 20px;font-size:15px;line-height:1.55;color:#5C5240">${body}</p>
    <a href="${url}" style="display:inline-block;background:#4F8340;color:#FFFDF7;text-decoration:none;font-weight:600;font-size:15px;padding:12px 22px;border-radius:999px">${action}</a>
    <p style="margin:22px 0 0;font-size:12px;line-height:1.5;color:#8B7C64">
      If the button does not work, paste this into your browser:<br>
      <span style="word-break:break-all">${url}</span>
    </p>
    <p style="margin:16px 0 0;font-size:12px;color:#8B7C64">
      If you did not ask for this, you can ignore it and nothing will happen.
    </p>
  </div>
</body></html>`;
}

export function verificationEmail(url: string): { html: string; text: string } {
  const body = "Confirm this address and your garden is ready. The link is good for one hour.";
  return {
    html: layout("Confirm your email", body, "Confirm email", url),
    text: `Confirm your email\n\n${body}\n\n${url}\n\n`
      + "If you did not ask for this, you can ignore it and nothing will happen.",
  };
}

export function resetPasswordEmail(url: string): { html: string; text: string } {
  const body = "Use this link to set a new password. It is good for one hour, and your "
    + "garden is untouched either way.";
  return {
    html: layout("Reset your password", body, "Set a new password", url),
    text: `Reset your password\n\n${body}\n\n${url}\n\n`
      + "If you did not ask for this, you can ignore it and nothing will happen.",
  };
}

/**
 * What a request carries once it has been through auth.
 *
 * Declared separately so route modules can type `c.get("user")` without
 * importing the app and creating a cycle.
 */

import type { Database } from "./db/client.js";
import type { Env } from "./env.js";

export interface AuthedUser {
  id: string;
  email: string;
  name: string;
}

export interface AppBindings {
  Bindings: Env;
  Variables: {
    db: Database;
    /** Only set on routes behind `requireAuth`. */
    user: AuthedUser;
  };
}

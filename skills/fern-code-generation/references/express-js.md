# Fern Express OpenAPI

## Goal

Generate the Express routing, request validation, response serialization, and error classes from an OpenAPI document with Fern, then implement only the endpoint business logic in handwritten service files.

Names such as `imdb`, `movies`, `Movie`, and `goodwill-hunting` in this skill are only examples. Replace them with the resource names, paths, schemas, and domain behavior from the user's OpenAPI document. Always inspect the generated files for the actual service class, method names, request types, response types, and error classes.

Prefer this shape:

```text
fern/
  fern.config.json
  generators.yml
  openapi/openapi.yml
src/
  api/index.ts
  api/generated/...
  services/<resource>.ts
  server.ts
```

## Minimal Fern Files

Create or update `fern/fern.config.json`:

```json
{
  "organization": "fern",
  "version": "<current-or-project-approved-fern-cli-version>"
}
```

Create or update `fern/generators.yml`:

```yaml
api:
  specs:
    - openapi: ./openapi/openapi.yml

default-group: local
groups:
  local:
    generators:
      - name: fernapi/fern-typescript-express
        version: <current-or-project-approved-generator-version>
        output:
          location: local-file-system
          path: ../src/api/generated
        config:
          outputSourceFiles: true
```

Use `fern/openapi/openapi.yml` as the source of truth. Do not keep an active `fern/definition/*.yml` source unless the user explicitly wants both. If migrating from Fern definitions, export first:

```bash
npm exec fern-api@<cli-version> -- export fern/openapi/openapi.yml
```

## OpenAPI Authoring Rules

Make `operationId` values stable; generated handler names may be normalized. Verify actual names in the generated `ImdbServiceMethods` or equivalent interface before implementing handlers.

Use schemas for request and response bodies. This example uses a movie API only to show the pattern:

```yaml
paths:
  /movies/create-movie:
    post:
      operationId: imdb_createMovie
      tags: [Imdb]
      requestBody:
        required: true
        content:
          application/json:
            schema:
              $ref: "#/components/schemas/CreateMovieRequest"
      responses:
        "200":
          content:
            application/json:
              schema:
                $ref: "#/components/schemas/MovieId"
  /movies/{movieId}:
    get:
      operationId: imdb_getMovie
      tags: [Imdb]
      parameters:
        - name: movieId
          in: path
          required: true
          schema:
            $ref: "#/components/schemas/MovieId"
      responses:
        "200":
          content:
            application/json:
              schema:
                $ref: "#/components/schemas/Movie"
        "404":
          description: Not found
```

Pay attention to:

- OpenAPI 404 responses often generate generic names such as `NotFoundError`, not custom Fern-definition names.
- Request schemas may be placed under `api/resources/<resource>/service/requests`, while shared schemas may move under `api/types`.
- The generated router may mount full OpenAPI paths internally. Check `src/api/generated/src/register.ts` and the generated service router before adding manual prefixes.
- Fern may emit generated tests under `src/api/generated/tests`; exclude them from the app `tsconfig` unless the project has matching test globals.

## Generate And Validate

Run:

```bash
npm exec fern-api@<cli-version> -- check
npm exec fern-api@<cli-version> -- generate --local --runner docker --force --no-prompt
```

Notes:

- `--local` uses Docker or Podman. Make sure the runtime is running.
- Remote generation may require `fern login` or `FERN_TOKEN`.
- If the CLI crashes on a very new Node runtime, update the `fern.config.json` CLI pin or run under an LTS Node version.
- If upgrading an existing project, prefer:

```bash
npm exec fern-api@<cli-version> -- generator upgrade --include-major --yes
```

## Handwritten App Integration

Create a stable app-level barrel so handwritten code can import generated exports:

```ts
// src/api/index.ts
export * from "./generated";
```

If the generator outputs a package-style layout under `src/api/generated/src`, keep a root compatibility barrel:

```ts
// src/api/generated/index.ts
export * from "./src";
```

Register generated services in the Express app. Replace `imdb` with each generated service key from `register.ts`:

```ts
// src/server.ts
import cors from "cors";
import express from "express";
import { register } from "./api/generated";
import imdb from "./services/imdb";

const PORT = process.env.PORT ?? 8080;
const app = express();

app.use(cors());

register(app, {
  imdb,
});

app.listen(PORT);
console.log(`Listening on port ${PORT}...`);
```

## Implement Endpoints

Open the generated service interface first. Replace the path below with the generated resource path for the current API:

```bash
sed -n '1,180p' src/api/generated/src/api/resources/imdb/service/ImdbService.ts
```

Implement exactly the method names and types it declares. This is a movie example; do not copy the domain logic unless the user's API is actually the same:

```ts
// src/services/imdb.ts
import { FernApi } from "../api";
import { ImdbService } from "../api/generated/src/api/resources/imdb/service/ImdbService";

export default new ImdbService({
  createmovie: (req, res) => {
    const id = req.body.title.toLowerCase().replaceAll(" ", "-");
    return res.send(id);
  },

  getmovie: (req, res) => {
    if (req.params.movieId === "goodwill-hunting") {
      return res.send({
        id: req.params.movieId,
        title: "Goodwill Hunting",
        rating: 4.9,
      });
    }

    throw new FernApi.NotFoundError();
  },
});
```

Rules:

- Do not hand-parse request bodies; generated routers parse and validate request schemas before calling handlers.
- Use `res.send(...)` with the response shape declared in OpenAPI.
- Throw generated Fern errors for documented non-2xx responses. Check generated `api/errors`.
- Return or await `res.send(...)` when convenient; generated response helpers are async.
- If TypeScript says handler names are missing, trust the generated interface over the OpenAPI casing.

## Compile And Runtime Test

Run:

```bash
yarn build
PORT=18080 node lib/server.js
```

In another terminal, test the documented paths. Replace these curl commands with endpoints from the user's OpenAPI document:

```bash
curl -i http://127.0.0.1:18080/movies/goodwill-hunting
curl -i -X POST http://127.0.0.1:18080/movies/create-movie \
  -H 'Content-Type: application/json' \
  --data '{"title":"Goodwill Hunting","rating":9.5,"genre":"COMEDY"}'
curl -i http://127.0.0.1:18080/movies/missing-movie
```

Expected checks:

- Successful GET returns `200` with a `Movie` JSON body.
- Successful POST returns `200` with a JSON `MovieId` string.
- Missing resource returns the documented error status, usually `404`.
- Unknown or invalid request bodies return generated validation errors, usually `422`.

Stop the server after testing. Do not leave long-running server sessions open.

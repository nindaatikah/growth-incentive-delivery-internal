// Optional S3 snapshot of the loaded data, so a restart serves data immediately
// instead of waiting for Databricks. Enabled when S3_BUCKET is set (Portal → File Storage).
import { GetObjectCommand, PutObjectCommand, S3Client } from "@aws-sdk/client-s3";
import { gunzipSync, gzipSync } from "node:zlib";

const bucket = process.env.S3_BUCKET;
const key = "snapshots/data.json.gz";
const s3 = bucket ? new S3Client({ region: "eu-central-1" }) : null;

export const snapshotEnabled = () => s3 !== null;

export async function readSnapshot<T>(): Promise<T | null> {
  if (!s3) return null;
  try {
    const res = await s3.send(new GetObjectCommand({ Bucket: bucket, Key: key }));
    const body = Buffer.from(await res.Body!.transformToByteArray());
    return JSON.parse(gunzipSync(body).toString("utf8")) as T;
  } catch (err) {
    const name = (err as { name?: string }).name;
    if (name !== "NoSuchKey") console.error("snapshot read failed:", err instanceof Error ? err.message : err);
    return null;
  }
}

export async function writeSnapshot(data: unknown) {
  if (!s3) return;
  try {
    const body = gzipSync(JSON.stringify(data));
    await s3.send(new PutObjectCommand({ Bucket: bucket, Key: key, Body: body, ContentType: "application/json", ContentEncoding: "gzip" }));
  } catch (err) {
    console.error("snapshot write failed:", err instanceof Error ? err.message : err);
  }
}

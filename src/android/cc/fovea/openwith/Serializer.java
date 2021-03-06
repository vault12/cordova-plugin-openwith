package cc.fovea.openwith;

import android.content.ClipData;
import android.content.ContentResolver;
import android.content.Context;
import android.content.Intent;
import android.database.Cursor;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;
import android.provider.MediaStore;
import android.provider.OpenableColumns;
import android.util.Base64;

import java.io.ByteArrayInputStream;
import java.io.File;
import java.io.FileNotFoundException;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.text.DateFormat;
import java.text.SimpleDateFormat;
import java.util.Calendar;
import java.util.Date;

import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;

/**
 * Handle serialization of Android objects ready to be sent to javascript.
 */
class Serializer {

    /** Convert an intent to JSON.
     *
     * This actually only exports stuff necessary to see file content
     * (streams or clip data) sent with the intent.
     * If none are specified, null is return.
     */
    public static JSONObject toJSONObject(
            final ContentResolver contentResolver,
            final Intent intent,
            final Context context)
            throws JSONException {

        String extraText = intent.getStringExtra(Intent.EXTRA_TEXT);

        JSONArray items = null;
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.KITKAT) {
            items = itemsFromClipData(contentResolver, intent.getClipData(), context, extraText);
        }
        if (items == null || items.length() == 0) {
            items = itemsFromExtras(contentResolver, intent.getExtras(), context);
        }
        if (items == null || items.length() == 0) {
            items = itemsFromData(contentResolver, intent.getData(), context);
        }
        if (items == null) {
            return null;
        }
        final JSONObject action = new JSONObject();
        action.put("action", translateAction(intent.getAction()));
        action.put("exit", readExitOnSent(intent.getExtras()));
        action.put("items", items);
        return action;
    }

    public static String translateAction(final String action) {
        if ("android.intent.action.SEND".equals(action) ||
            "android.intent.action.SEND_MULTIPLE".equals(action)) {
            return "SEND";
        } else if ("android.intent.action.VIEW".equals(action)) {
            return "VIEW";
        }
        return action;
    }

    /** Read the value of "exit_on_sent" in the intent's extra.
     *
     * Defaults to false. */
    public static boolean readExitOnSent(final Bundle extras) {
        if (extras == null) {
            return false;
        }
        return extras.getBoolean("exit_on_sent", false);
    }

    /** Extract the list of items from clip data (if available).
     *
     * Defaults to null. */
    public static JSONArray itemsFromClipData(
            final ContentResolver contentResolver,
            final ClipData clipData,
            final Context context,
            final String extraString)
            throws JSONException {
        if (clipData != null) {
            final int clipItemCount = clipData.getItemCount();
            JSONObject[] items = new JSONObject[clipItemCount];
            for (int i = 0; i < clipItemCount; i++) {
                ClipData.Item item = clipData.getItemAt(i);
                String text = item.getText() != null ? (String)item.getText() : extraString;
                items[i] = toJSONObject(contentResolver, context, item.getUri(), text);
            }
            return new JSONArray(items);
        }
        return null;
    }

    /** Extract the list of items from the intent's extra stream.
     *
     * See Intent.EXTRA_STREAM for details. */
    public static JSONArray itemsFromExtras(
            final ContentResolver contentResolver,
            final Bundle extras,
            final Context context)
            throws JSONException {
        if (extras == null) {
            return null;
        }
        final JSONObject item = toJSONObject(
                contentResolver,
                context,
                (Uri) extras.get(Intent.EXTRA_STREAM),
                null);
        if (item == null) {
            return null;
        }
        final JSONObject[] items = new JSONObject[1];
        items[0] = item;
        return new JSONArray(items);
    }

    /** Extract the list of items from the intent's getData
     *
     * See Intent.ACTION_VIEW for details. */
    public static JSONArray itemsFromData(
            final ContentResolver contentResolver,
            final Uri uri,
            final Context context)
            throws JSONException {
        if (uri == null) {
            return null;
        }
        final JSONObject item = toJSONObject(
                contentResolver,
                context,
                uri,
                null);
        if (item == null) {
            return null;
        }
        final JSONObject[] items = new JSONObject[1];
        items[0] = item;
        return new JSONArray(items);
    }

    /** Convert an Uri to JSON object.
     *
     * Object will include:
     *    "type" of data;
     *    "uri" itself;
     *    "path" to the file, if applicable.
     *    "data" for the file.
     */
    public static JSONObject toJSONObject(
            final ContentResolver contentResolver,
            final Context context,
            final Uri uri,
            final String text
            )
            throws JSONException {
        if (uri == null && text == null) {
            return null;
        }

        final JSONObject json = new JSONObject();
        String type = null;
        String name = null;
        InputStream inputStream = null;

        if (text != null) {
            String pattern = "dd.MM.yyyy HH.mm.ss";
            DateFormat df = new SimpleDateFormat(pattern);
            Date today = Calendar.getInstance().getTime();
            String dateStr = df.format(today);

            name = "New File " + dateStr + ".txt";
            type = "text/plain";
            inputStream = new ByteArrayInputStream(text.getBytes());

        } else {
            json.put("uri", uri);
            json.put("path", getRealPathFromURI(contentResolver, uri));
            Cursor returnCursor =
                    contentResolver.query(uri, null, null, null, null);
            int nameIndex = returnCursor.getColumnIndex(OpenableColumns.DISPLAY_NAME);
            returnCursor.moveToFirst();
            name = returnCursor.getString(nameIndex);
            type = contentResolver.getType(uri);
            try {
                inputStream = contentResolver.openInputStream(uri);
            } catch (FileNotFoundException e) {
                e.printStackTrace();
            }
        }

        // create cache sub dir
        File shareDir = new File(context.getCacheDir(), "com_vault12_vault12_openWith_shared");
        if (!shareDir.exists()) {
            shareDir.mkdir();
        }
        // clear previous hanged files
        String[] children = shareDir.list();
        for (String child : children) {
            new File(shareDir, child).delete();
        }

        String shareDirPath = shareDir.getAbsolutePath();
        String filepath = shareDirPath + File.separator + name;
        json.put("type", type);
        json.put("name", name);

        // copy file to cache dir and set filepath
        if (inputStream != null) {
            try {
                File f = new File(filepath);
                f.setWritable(true, false);
                FileOutputStream outputStream = new FileOutputStream(f);
                byte buffer[] = new byte[1024];
                int length = 0;
                while ((length = inputStream.read(buffer)) > 0) {
                    outputStream.write(buffer, 0, length);
                }
                outputStream.close();
                inputStream.close();

                json.put("filepath", filepath);

            } catch (IOException e) {
                e.printStackTrace();
            }
        }

        return json;
    }

    /** Return data contained at a given Uri as Base64. Defaults to null. */
    public static String getDataFromURI(
            final ContentResolver contentResolver,
            final Uri uri) {
        try {
            final InputStream inputStream = contentResolver.openInputStream(uri);
            final byte[] bytes = ByteStreams.toByteArray(inputStream);
            return Base64.encodeToString(bytes, Base64.NO_WRAP);
        }
        catch (IOException e) {
            return "";
        }
    }

	/** Convert the Uri to the direct file system path of the image file.
     *
     * source: https://stackoverflow.com/questions/20067508/get-real-path-from-uri-android-kitkat-new-storage-access-framework/20402190?noredirect=1#comment30507493_20402190 */
	public static String getRealPathFromURI(
            final ContentResolver contentResolver,
            final Uri uri) {
		final String[] proj = { MediaStore.Images.Media.DATA };
		final Cursor cursor = contentResolver.query(uri, proj, null, null, null);
		if (cursor == null) {
			return "";
		}
		final int column_index = cursor.getColumnIndex(MediaStore.Images.Media.DATA);
		if (column_index < 0) {
			cursor.close();
			return "";
		}
		cursor.moveToFirst();
		final String result = cursor.getString(column_index);
		cursor.close();
		return result;
	}
}
// vim: ts=4:sw=4:et

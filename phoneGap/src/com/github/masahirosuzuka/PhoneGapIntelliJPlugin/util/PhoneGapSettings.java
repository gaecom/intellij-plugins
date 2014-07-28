package com.github.masahirosuzuka.PhoneGapIntelliJPlugin.util;

import com.intellij.execution.configurations.PathEnvironmentVariableUtil;
import com.intellij.openapi.components.*;
import com.intellij.openapi.util.SystemInfo;
import com.intellij.openapi.util.text.StringUtil;
import com.intellij.util.containers.ContainerUtil;
import org.jetbrains.annotations.NotNull;
import org.jetbrains.annotations.Nullable;

import java.io.File;
import java.util.List;

/**
 * PhoneGapSettings.java
 * <p/>
 * Created by Masahiro Suzuka on 2014/04/12.
 */
@State(
  name = "PhoneGapSettings",
  storages = {@Storage(
    file = StoragePathMacros.APP_CONFIG + "/phonegap.xml")})
public final class PhoneGapSettings implements PersistentStateComponent<PhoneGapSettings.State> {


  // External tools PATH
  public static String NODEJS_PATH = "/usr/local/bin/node";
  public static String ANDROID_SDK = "android";
  public static String IOS_SIM = "ios-sim";

  // PhoneGap commands
  public static String PHONEGAP_PLATFORM_ANDROID = "android";
  public static String PHONEGAP_PLATFORM_IOS = "ios";
  public static String PHONEGAP_PLATFORM_WP = "windowsphone";
  public static String PHONEGAP_PLATFORM_RIPPLE = "ripple";


  public static class State {
    //don't touch for back compatibility
    public String phoneGapExecutablePath;
    public String cordovaExecutablePath;

    public String executablePath;

    @Override
    public boolean equals(Object o) {
      if (!(o instanceof State)) return false;

      return StringUtil.equals(getExecutablePath(), ((State)o).getExecutablePath());
    }

    @Override
    public int hashCode() {
      return String.valueOf(getExecutablePath()).hashCode();
    }

    public String getExecutablePath() {
      if (!StringUtil.isEmpty(phoneGapExecutablePath)) {
        executablePath = phoneGapExecutablePath;
        phoneGapExecutablePath = null;
      }
      else if (!StringUtil.isEmpty(cordovaExecutablePath)) {
        executablePath = cordovaExecutablePath;
        cordovaExecutablePath = null;
      }

      if (StringUtil.isEmpty(executablePath)) {
        executablePath = detectDefaultPath();
      }

      return executablePath;
    }
  }

  public static PhoneGapSettings getInstance() {
    return ServiceManager.getService(PhoneGapSettings.class);
  }

  private State myState = new State();

  @NotNull
  @Override
  public State getState() {
    return myState;
  }

  @Nullable
  public String getExecutablePath() {
    return myState.getExecutablePath();
  }

  @Override
  public void loadState(State state) {
    myState = state;
  }

  @Nullable
  private static String detectDefaultPath() {
    return ContainerUtil.getFirstItem(getDefaultPaths());
  }

  @NotNull
  public static List<String> getDefaultPaths() {
    List<String> paths = ContainerUtil.newArrayList();
    ContainerUtil.addIfNotNull(paths, getCordovaDefaultPath());
    ContainerUtil.addIfNotNull(paths, getPhonegapDefaultPath());
    return paths;
  }

  @Nullable
  public static String getCordovaDefaultPath() {
    File path = PathEnvironmentVariableUtil.findInPath(SystemInfo.isWindows ? "cordova.cmd" : "cordova");
    return (path != null && path.exists()) ? path.getAbsolutePath() : null;
  }

  @Nullable
  public static String getPhonegapDefaultPath() {
    File path = PathEnvironmentVariableUtil.findInPath(SystemInfo.isWindows ? "phonegap.cmd" : "phonegap");
    return (path != null && path.exists()) ? path.getAbsolutePath() : null;
  }
}

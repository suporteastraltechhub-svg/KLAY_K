plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    // Gera os recursos do Firebase (FCM) a partir de android/app/google-services.json.
    // Utilizado SOMENTE como transporte; Supabase continua o backend.
    id("com.google.gms.google-services")
}

import java.io.FileInputStream
import java.util.Properties

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "com.klayk.klay_k"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = "29.0.14206865"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.klayk.klay_k"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            storeFile = keystoreProperties["storeFile"]?.let { file(it) }
            storePassword = keystoreProperties["storePassword"] as String?
            keyAlias = keystoreProperties["keyAlias"] as String?
            keyPassword = keystoreProperties["keyPassword"] as String?
        }
    }

    // O plugin do Flutter faz `abiFilters.clear()` e reinsere todos os ABIs
    // padrao, ignorando o filtro por buildType. Como o snapshot AOT do Dart
    // (libapp.so) so existe para arm64-v8a, os plugins ainda empacotavam
    // libs de armeabi-v7a e x86_64 — o APK ficaria instalavel nesses ABIs e
    // quebraria ao abrir por falta do libapp.so. `packaging` e avaliado na
    // hora de empacotar, depois do plugin, entao o filtro aqui e definitivo.
    packaging {
        jniLibs {
            excludes += setOf("**/armeabi-v7a/**", "**/x86/**", "**/x86_64/**")
        }
    }

    lint {
        // O Lint "vital" roda analise estatica Java/Kotlin e estoura a memoria
        // desta maquina de build (o processo era morto por OOM). Isso nao
        // afeta o runtime: a verificacao do lado Dart continua sendo feita por
        // `flutter analyze` (ver `analysis_options.yaml`).
        checkReleaseBuilds = false
        abortOnError = false
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
            // O snapshot AOT do Dart (libapp.so) e gerado apenas para
            // arm64-v8a, mas os plugins empacotavam libs nativas de
            // armeabi-v7a e x86_64 tambem. Sem este filtro o APK seria
            // instalavel nesses ABIs e quebraria ao abrir por falta do
            // libapp.so. Filtrando, o pacote contem so o ABI com AOT.
            ndk {
                abiFilters += listOf("arm64-v8a")
            }
            // Minificacao R8 desligada: o processo de R8 era morto por OOM
            // nesta maquina (memoria limitada) e ela e apenas uma otimizacao
            // opcional. As regras ficam prontas em app/proguard-rules.pro para
            // reativa-la com seguranca.
            isMinifyEnabled = false
            isShrinkResources = false
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }
}

flutter {
    source = "../.."
}
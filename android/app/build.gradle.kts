// MUDANÇA 1: Adicionando os imports que faltavam para ler o arquivo de senhas.
import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

// Lógica para ler o arquivo key.properties
val keyProperties = Properties()
// MUDANÇA 2: Usando um caminho mais robusto para o arquivo.
// Garanta que seu arquivo 'key.properties' está na pasta 'android'.
val keyPropertiesFile = rootProject.file("key.properties") 
if (keyPropertiesFile.exists()) {
    keyProperties.load(FileInputStream(keyPropertiesFile))
}

android {
    namespace = "com.str1nng.keyfinder" // Usando seu namespace customizado
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        // Usando Java 8 para maior compatibilidade, como no nosso último reset bem-sucedido
        sourceCompatibility = JavaVersion.VERSION_1_8
        targetCompatibility = JavaVersion.VERSION_1_8
    }

    kotlinOptions {
        jvmTarget = "1.8"
    }

    // MUDANÇA 3: A configuração de assinatura foi movida para o lugar padrão
    signingConfigs {
        if (keyPropertiesFile.exists()) {
            create("release") {
                keyAlias = keyProperties["keyAlias"] as String?
                keyPassword = keyProperties["keyPassword"] as String?
                storeFile = if (keyProperties["storeFile"] != null) file(keyProperties["storeFile"] as String) else null
                storePassword = keyProperties["storePassword"] as String?
            }
        }
    }

    defaultConfig {
        applicationId = "com.str1nng.keyfinder"
        minSdk = flutter.minSdkVersion // minSdk do Flutter
        targetSdk = 34
        versionCode = 1
        versionName = "1.0"
    }

    buildTypes {
        release {
            signingConfig = if (keyPropertiesFile.exists()) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    implementation(kotlin("stdlib-jdk7"))
    implementation("androidx.annotation:annotation:1.8.1")
    // Mantendo o .jar local, como você pediu
    implementation(files("libs/TarsosDSP-Android-2.4.jar"))
    testImplementation("junit:junit:4.13.2")
}

// The tabs of the settings dialog, in the order they are shown
// From Netspeed Widget 3.1 (Daniel Faust). Modified 2026 for the fork (io.github.zebieksterc.netspeedwidget); see ChangeLog.
import QtQuick 2.2
import org.kde.plasma.configuration 2.0

ConfigModel {
    ConfigCategory {
         name: i18n('General')
         icon: 'preferences-desktop-color'
         source: 'config/ConfigGeneral.qml'
    }
    ConfigCategory {
         name: i18n('Appearance')
         icon: 'preferences-desktop-theme-global'
         source: 'config/ConfigAppearance.qml'
    }
    ConfigCategory {
         name: i18n('Connection')
         icon: 'network-connect'
         source: 'config/ConfigConnection.qml'
    }
    ConfigCategory {
         name: i18n('Data limits')
         icon: 'office-chart-pie'
         source: 'config/ConfigLimits.qml'
    }
    ConfigCategory {
         name: i18n('Advanced')
         icon: 'preferences-desktop-launch-feedback'
         source: 'config/ConfigAdvanced.qml'
    }
}

package cl.duoc.mi_foro_usuarios.service;

import org.springframework.security.core.userdetails.User;
import org.springframework.security.core.userdetails.UserDetails;
import org.springframework.security.core.userdetails.UserDetailsService;
import org.springframework.security.core.userdetails.UsernameNotFoundException;
import org.springframework.stereotype.Service;

import cl.duoc.mi_foro_usuarios.entity.UsuarioEntity;
import cl.duoc.mi_foro_usuarios.repository.UsuarioRepository;

@Service 
public class CustomUserDetailsService implements UserDetailsService{

    private final UsuarioRepository usuarioRepository;

    public CustomUserDetailsService(UsuarioRepository usuarioRepository) {
        this.usuarioRepository = usuarioRepository;
    }


    @Override 
    public UserDetails loadUserByUsername(String username) throws UsernameNotFoundException {
        UsuarioEntity usuario = usuarioRepository.findByUsuario(username).orElseThrow(() -> new UsernameNotFoundException("Usuario no encontrado"));

        return User.builder()
        .username(usuario.getUsuario())
        .password(usuario.getPassword())
        .roles(usuario.getTipoUsuario().getNombre())
        .disabled(usuario.getActivo() != 1 || usuario.getTipoUsuario().getActivo() != 1)
        .build();
    }
}
